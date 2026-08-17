import Foundation

public struct MonitorService: Sendable {
    public let policy: MonitorPolicy
    private let runner: ProcessRunner

    public init(policy: MonitorPolicy = PolicyLoader.load(), runner: ProcessRunner = ProcessRunner()) {
        self.policy = policy
        self.runner = runner
    }

    public func inspect(reputationConsents: Set<String> = []) async -> SecuritySnapshot {
        let proxy = ProxyInspector.inspect()

        async let proxyAndTunnel = inspectProxyAndTunnel(proxy)
        async let ipv6 = inspectIPv6Reachability()
        async let tls = inspectTLS(proxy: proxy)
        async let claude = inspectClaudeApp()

        let exitInspection = await inspectExitVerification(proxy: proxy)
        let reputation = await inspectNodeReputation(
            address: exitInspection.stableAddress,
            proxy: proxy,
            consented: exitInspection.stableAddress.map(reputationConsents.contains) ?? false
        )
        let otherChecks = await [proxyAndTunnel, ipv6, tls, claude]

        return SecuritySnapshot(
            checks: [exitInspection.result, reputation] + otherChecks,
            blockingActive: false
        )
    }

    private struct ExitInspection: Sendable {
        let result: CheckResult
        let stableAddress: String?
    }

    private func inspectExitVerification(proxy: ProxySnapshot) async -> ExitInspection {
        let providers = [
            (name: "ipify", url: "https://api.ipify.org"),
            (name: "ifconfig.me", url: "https://ifconfig.me/ip")
        ]
        let requestedCount = min(max(policy.exitSampleCount, 3), 5)
        var samples: [ExitSample] = []

        for index in 0..<requestedCount {
            let provider = providers[index % providers.count]
            let result = await runner.run(
                executable: "/usr/bin/curl",
                arguments: curlArguments(proxy: proxy, url: provider.url),
                timeout: 12
            )
            if result.exitCode == 0,
               let address = ProbeParsers.firstIPv4(in: result.output) {
                samples.append(ExitSample(provider: provider.name, address: address))
            }
        }

        let uniqueAddresses = Set(samples.map(\.address))
        var metadata: ExitMetadata?
        if uniqueAddresses.count == 1, let address = uniqueAddresses.first {
            metadata = await fetchExitMetadata(address: address, proxy: proxy)
        }

        let evidence = ExitVerificationEvidence(
            requestedSampleCount: requestedCount,
            samples: samples,
            metadata: metadata,
            explicitProxyURL: proxy.preferredProxyURL
        )
        let stableAddress = samples.count == requestedCount && uniqueAddresses.count == 1
            ? uniqueAddresses.first
            : nil
        return ExitInspection(
            result: ExitVerification.evaluate(
                evidence: evidence,
                policy: policy
            ),
            stableAddress: stableAddress
        )
    }

    private func inspectNodeReputation(
        address: String?,
        proxy: ProxySnapshot,
        consented: Bool
    ) async -> CheckResult {
        guard let address, consented else {
            return NodeReputationAssessment.evaluate(
                address: address,
                lookupConsented: consented,
                response: nil
            )
        }

        let result = await runner.run(
            executable: "/usr/bin/curl",
            arguments: curlArguments(
                proxy: proxy,
                url: "https://reputation.noc.org/api/?ip=\(address)"
            ),
            timeout: 12
        )
        let response = result.exitCode == 0
            ? try? JSONDecoder().decode(
                NodeReputationResponse.self,
                from: Data(result.output.utf8)
            )
            : nil
        return NodeReputationAssessment.evaluate(
            address: address,
            lookupConsented: true,
            response: response
        )
    }

    private func fetchExitMetadata(address: String, proxy: ProxySnapshot) async -> ExitMetadata? {
        let result = await runner.run(
            executable: "/usr/bin/curl",
            arguments: curlArguments(
                proxy: proxy,
                url: "https://ipwho.is/\(address)"
            ),
            timeout: 12
        )
        guard result.exitCode == 0,
              let response = try? JSONDecoder().decode(
                  IPWhoResponse.self,
                  from: Data(result.output.utf8)
              )
        else { return nil }
        return response.metadata(expectedAddress: address)
    }

    private func curlArguments(proxy: ProxySnapshot, url: String) -> [String] {
        var arguments = [
            "-4", "-fsS", "--connect-timeout", "5", "--max-time", "10",
            "--user-agent", "ClaudeMacGuard/0.2.0"
        ]
        if let proxyURL = proxy.preferredProxyURL {
            arguments += ["--proxy", proxyURL]
        }
        arguments.append(url)
        return arguments
    }

    private func inspectProxyAndTunnel(_ proxy: ProxySnapshot) async -> CheckResult {
        var details = proxy.descriptions
        if !proxy.tunnelInterfaces.isEmpty {
            details.append("活动隧道接口：\(proxy.tunnelInterfaces.joined(separator: ", "))")
        }

        if proxy.hasSystemProxy {
            return CheckResult(
                id: "proxy-tunnel",
                title: "代理 / TUN",
                state: .passed,
                summary: "检测到启用的系统代理",
                details: details + ["是否为预期代理仍需与出口 IP 一起判断。"]
            )
        }

        if proxy.hasTunnel {
            return CheckResult(
                id: "proxy-tunnel",
                title: "代理 / TUN",
                state: .warning,
                summary: "检测到 TUN 类接口，但无法仅凭接口名确认其身份",
                details: details
            )
        }

        return CheckResult(
            id: "proxy-tunnel",
            title: "代理 / TUN",
            state: policy.requireProxyOrTunnel ? .failed : .passed,
            summary: policy.requireProxyOrTunnel ? "未检测到系统代理或活动隧道" : "策略未要求代理或隧道",
            details: details
        )
    }

    private func inspectIPv6Reachability() async -> CheckResult {
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key.lowercased().contains("proxy") {
            environment.removeValue(forKey: key)
        }

        let result = await runner.run(
            executable: "/usr/bin/curl",
            arguments: [
                "-6", "-sS", "-o", "/dev/null",
                "-w", "remote_ip=%{remote_ip} http=%{http_code}",
                "--connect-timeout", "3", "--max-time", "6",
                "https://\(policy.apiHost)/"
            ],
            environment: environment,
            timeout: 8
        )

        let interpretation = IPv6ProbeInterpretation.interpret(
            remoteIP: ProbeParsers.curlRemoteIP(in: result.output),
            commandSucceeded: result.exitCode == 0
        )

        switch interpretation {
        case .unreachable:
            return CheckResult(
                id: "ipv6",
                title: "IPv6 可达性",
                state: .passed,
                summary: "未发现到 \(policy.apiHost) 的可用 IPv6 路径",
                details: ["这是一次独立探测，不代表系统级阻断已经启用。"]
            )
        case let .fakeIPv4Mapping(address):
            return CheckResult(
                id: "ipv6",
                title: "IPv6 可达性",
                state: .passed,
                summary: "只观察到 fake-IP / IPv4 映射",
                details: [address]
            )
        case let .publicReachability(address):
            return CheckResult(
                id: "ipv6",
                title: "IPv6 可达性",
                state: .failed,
                summary: "\(policy.apiHost) 可经 IPv6 到达",
                details: [address, "v0.2 尚不能阻止 Claude 使用这条路径。"]
            )
        case let .malformed(reason):
            return CheckResult(
                id: "ipv6",
                title: "IPv6 可达性",
                state: .unavailable,
                summary: "IPv6 探测结果无法解释",
                details: [reason]
            )
        }
    }

    private func inspectTLS(proxy: ProxySnapshot) async -> CheckResult {
        var arguments = ["-4", "-vI", "--connect-timeout", "8", "--max-time", "15"]
        if let proxyURL = proxy.preferredProxyURL {
            arguments += ["--proxy", proxyURL]
        }
        arguments.append("https://\(policy.apiHost)/")

        let result = await runner.run(
            executable: "/usr/bin/curl",
            arguments: arguments,
            timeout: 17
        )
        guard result.exitCode == 0 else {
            return CheckResult(
                id: "tls",
                title: "TLS",
                state: .failed,
                summary: "无法完成 \(policy.apiHost) 的 TLS 验证",
                details: [result.timedOut ? "连接超时" : "curl 退出码 \(result.exitCode)"]
            )
        }

        if let proxyURL = proxy.preferredProxyURL,
           !result.output.contains("CONNECT \(policy.apiHost):443"),
           !result.output.contains("CONNECT tunnel established") {
            return CheckResult(
                id: "tls",
                title: "TLS",
                state: .failed,
                summary: "配置了代理，但探测未观察到 HTTP CONNECT",
                details: [proxyURL]
            )
        }

        guard let issuer = ProbeParsers.tlsIssuer(in: result.output) else {
            return CheckResult(
                id: "tls",
                title: "TLS",
                state: .warning,
                summary: "TLS 连接成功，但未能读取证书颁发者",
                details: ["curl 未使用跳过证书验证选项。"]
            )
        }

        let suspicious = ProbeParsers.looksLikeInterceptingIssuer(issuer)
        return CheckResult(
            id: "tls",
            title: "TLS",
            state: suspicious ? .failed : .passed,
            summary: suspicious ? "证书颁发者疑似本地拦截工具" : "TLS 验证完成",
            details: ["Issuer: \(issuer)"]
        )
    }

    private func inspectClaudeApp() async -> CheckResult {
        let path = policy.claudeAppPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return CheckResult(
                id: "claude-app",
                title: "Claude.app",
                state: .failed,
                summary: "未在预期位置找到 Claude.app",
                details: [path]
            )
        }

        let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
        let verification = await runner.run(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", path],
            timeout: 15
        )
        let description = await runner.run(
            executable: "/usr/bin/codesign",
            arguments: ["-d", "--verbose=4", path],
            timeout: 15
        )
        let teamID = ProbeParsers.codeSignField("TeamIdentifier", in: description.output)

        var details = ["Path: \(path)"]
        details.append("Bundle ID: \(bundleID ?? "unknown")")
        details.append("Team ID: \(teamID ?? "unknown")")

        guard verification.exitCode == 0 else {
            return CheckResult(
                id: "claude-app",
                title: "Claude.app",
                state: .failed,
                summary: "Claude.app 代码签名验证失败",
                details: details
            )
        }
        guard bundleID == policy.expectedClaudeBundleIdentifier,
              teamID == policy.expectedClaudeTeamIdentifier else {
            return CheckResult(
                id: "claude-app",
                title: "Claude.app",
                state: .failed,
                summary: "Claude.app 身份与本地预期不一致",
                details: details
            )
        }

        return CheckResult(
            id: "claude-app",
            title: "Claude.app",
            state: .passed,
            summary: "应用存在，签名、Bundle ID 与 Team ID 符合预期",
            details: details
        )
    }
}
