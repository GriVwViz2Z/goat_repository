import ClaudeMacGuardCore
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(description: message) }
}

private func runTests() throws {
    try expect(
        IPv4Policy.integer(from: "203.0.113.10") == 3_405_803_786,
        "IPv4 integer conversion"
    )
    try expect(IPv4Policy.integer(from: "203.0.113") == nil, "reject short IPv4")
    try expect(IPv4Policy.integer(from: "203.0.113.999") == nil, "reject invalid octet")
    try expect(
        IPv4Policy.contains(address: "203.0.113.10", cidr: "203.0.113.0/24"),
        "CIDR positive match"
    )
    try expect(
        !IPv4Policy.contains(address: "203.0.114.10", cidr: "203.0.113.0/24"),
        "CIDR negative match"
    )
    try expect(
        IPv4Policy.contains(address: "192.0.2.1", cidr: "0.0.0.0/0"),
        "CIDR zero prefix"
    )
    try expect(
        IPv6ProbeInterpretation.interpret(
            remoteIP: "::ffff:198.18.0.42",
            commandSucceeded: true
        ) == .fakeIPv4Mapping("::ffff:198.18.0.42"),
        "Mihomo fake-IP interpretation"
    )
    try expect(
        IPv6ProbeInterpretation.interpret(
            remoteIP: "2001:db8::42",
            commandSucceeded: true
        ) == .publicReachability("2001:db8::42"),
        "public IPv6 interpretation"
    )
    try expect(
        ProbeParsers.curlRemoteIP(in: "remote_ip=2001:db8::1 http=200") == "2001:db8::1",
        "curl remote IP parser"
    )
    try expect(
        ProbeParsers.tlsIssuer(in: "* issuer: C=US; O=Example CA\n* done") == "C=US; O=Example CA",
        "TLS issuer parser"
    )
    try expect(
        ProbeParsers.tlsIssuer(in: "* 证书信息 ISSUER: C=US; O=Unicode CA\n* done") == "C=US; O=Unicode CA",
        "TLS issuer parser with Unicode prefix and case-insensitive marker"
    )
    try expect(ProbeParsers.looksLikeInterceptingIssuer("Charles Proxy CA"), "MITM marker")
    try expect(!ProbeParsers.looksLikeInterceptingIssuer("DigiCert Inc"), "public CA marker")

    let signature = "Identifier=com.anthropic.claudefordesktop\nTeamIdentifier=Q6L2SF6YDW\n"
    try expect(
        ProbeParsers.codeSignField("TeamIdentifier", in: signature) == "Q6L2SF6YDW",
        "codesign parser"
    )

    let snapshot = SecuritySnapshot(checks: [
        CheckResult(id: "a", title: "A", state: .passed, summary: "ok"),
        CheckResult(id: "b", title: "B", state: .failed, summary: "bad")
    ])
    try expect(snapshot.overallState == .failed, "failed check dominates summary")
    try expect(!snapshot.blockingActive, "v0.2 launch gate must not claim network blocking")

    let readyForLaunch = SecuritySnapshot(checks: [
        CheckResult(id: "exit-verification", title: "出口验证", state: .passed, summary: "ok"),
        CheckResult(id: "node-reputation", title: "节点公开信誉", state: .warning, summary: "advisory"),
        CheckResult(id: "proxy-tunnel", title: "代理 / TUN", state: .passed, summary: "ok"),
        CheckResult(id: "ipv6", title: "IPv6 可达性", state: .passed, summary: "ok"),
        CheckResult(id: "tls", title: "TLS", state: .passed, summary: "ok"),
        CheckResult(id: "claude-app", title: "Claude.app", state: .passed, summary: "ok")
    ])
    try expect(
        LaunchGate.evaluate(readyForLaunch).isReady,
        "advisory reputation warning must not silently redefine the local launch policy"
    )

    let unsafeIPv6 = SecuritySnapshot(checks: readyForLaunch.checks.map { check in
        guard check.id == "ipv6" else { return check }
        return CheckResult(
            id: check.id,
            title: check.title,
            state: .failed,
            summary: "public IPv6 path"
        )
    })
    let blockedLaunch = LaunchGate.evaluate(unsafeIPv6)
    try expect(!blockedLaunch.isReady, "public IPv6 path must block v0.2 launch")
    try expect(
        blockedLaunch.blockingReasons.contains(where: { $0.contains("public IPv6 path") }),
        "launch gate explains the failing check"
    )

    let missingTLS = SecuritySnapshot(
        checks: readyForLaunch.checks.filter { $0.id != "tls" }
    )
    try expect(
        !LaunchGate.evaluate(missingTLS).isReady,
        "missing mandatory evidence must block v0.2 launch"
    )

    let metadata = ExitMetadata(
        address: "203.0.113.10",
        city: "Tokyo",
        region: "Tokyo",
        countryCode: "JP",
        countryName: "Japan",
        asn: "15169",
        organization: "Example Network"
    )
    let stableEvidence = ExitVerificationEvidence(
        requestedSampleCount: 3,
        samples: [
            ExitSample(provider: "ipify", address: "203.0.113.10"),
            ExitSample(provider: "ifconfig.me", address: "203.0.113.10"),
            ExitSample(provider: "ipify", address: "203.0.113.10")
        ],
        metadata: metadata,
        explicitProxyURL: "http://127.0.0.1:1082"
    )
    let noRules = ExitVerification.evaluate(evidence: stableEvidence, policy: MonitorPolicy())
    try expect(noRules.state == .warning, "identified exit is not trusted without rules")
    try expect(
        noRules.actions == [.confirmExitIPv4("203.0.113.10")],
        "stable proxied exit can be proposed for explicit trust"
    )

    let exactIP = ExitVerification.evaluate(
        evidence: stableEvidence,
        policy: MonitorPolicy(allowedExitIPv4: ["203.0.113.10"])
    )
    try expect(exactIP.state == .passed, "exact trusted IP verifies an exit")
    try expect(exactIP.actions.isEmpty, "confirmed exit needs no confirmation action")

    let CIDR = ExitVerification.evaluate(
        evidence: stableEvidence,
        policy: MonitorPolicy(allowedExitCIDRs: ["203.0.113.0/24"])
    )
    try expect(CIDR.state == .passed, "trusted CIDR verifies an exit")

    let wrongIP = ExitVerification.evaluate(
        evidence: stableEvidence,
        policy: MonitorPolicy(allowedExitIPv4: ["203.0.113.99"])
    )
    try expect(wrongIP.state == .failed, "untrusted IP must fail")
    try expect(
        wrongIP.actions == [.confirmExitIPv4("203.0.113.10")],
        "untrusted stable IP can be proposed for explicit trust"
    )

    let noMetadataEvidence = ExitVerificationEvidence(
        requestedSampleCount: stableEvidence.requestedSampleCount,
        samples: stableEvidence.samples,
        metadata: nil,
        explicitProxyURL: stableEvidence.explicitProxyURL
    )
    let noMetadata = ExitVerification.evaluate(
        evidence: noMetadataEvidence,
        policy: MonitorPolicy(allowedExitIPv4: ["203.0.113.10"])
    )
    try expect(noMetadata.state == .passed, "metadata is informational, not a trust rule")

    let rotatingEvidence = ExitVerificationEvidence(
        requestedSampleCount: 3,
        samples: [
            ExitSample(provider: "ipify", address: "203.0.113.10"),
            ExitSample(provider: "ifconfig.me", address: "203.0.113.11"),
            ExitSample(provider: "ipify", address: "203.0.113.10")
        ],
        metadata: nil,
        explicitProxyURL: "http://127.0.0.1:1082"
    )
    let rotating = ExitVerification.evaluate(evidence: rotatingEvidence, policy: MonitorPolicy())
    try expect(rotating.state == .failed, "rotating exit must fail under stable policy")
    try expect(rotating.actions.isEmpty, "rotating exit cannot be confirmed from the UI")

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeMacGuardSelfTest-\(UUID().uuidString)")
    let tempPolicyURL = tempRoot.appendingPathComponent("policy.json")
    defer { try? FileManager.default.removeItem(at: tempRoot) }
    try PolicyStore.confirmExitIPv4("203.0.113.10", at: tempPolicyURL)
    try PolicyStore.confirmExitIPv4("203.0.113.10", at: tempPolicyURL)
    let storedPolicy = PolicyLoader.load(from: tempPolicyURL)
    try expect(
        storedPolicy.allowedExitIPv4 == ["203.0.113.10"],
        "trust action persists one exact IP without duplicates"
    )

    let metadataJSON = """
    {
      "ip": "203.0.113.10",
      "success": true,
      "country": "Japan",
      "country_code": "JP",
      "region": "Tokyo",
      "city": "Tokyo",
      "connection": {
        "asn": 15169,
        "org": "Example Network"
      }
    }
    """
    let decodedMetadata = try JSONDecoder()
        .decode(IPWhoResponse.self, from: Data(metadataJSON.utf8))
        .metadata(expectedAddress: "203.0.113.10")
    try expect(decodedMetadata?.asn == "AS15169", "ipwho.is ASN parser")
    try expect(decodedMetadata?.countryCode == "JP", "ipwho.is country parser")

    let cleanReputationJSON = """
    {
      "ip": "203.0.113.10",
      "reverse": "exit.example.net",
      "as_number": "64500",
      "as_name": "EXAMPLE-NET",
      "country_code": "JP",
      "country": "Japan",
      "usage": {
        "is_tor": false,
        "is_proxy": true,
        "is_hosting": true,
        "is_routable": true
      },
      "reputation": {
        "web_spam": false,
        "web_attacks": false,
        "botnet": false,
        "email_spam": false,
        "brute_force": false,
        "ddos": false
      },
      "recommendations": { "block_traffic": false }
    }
    """
    let cleanReputation = try JSONDecoder().decode(
        NodeReputationResponse.self,
        from: Data(cleanReputationJSON.utf8)
    )
    let notQueried = NodeReputationAssessment.evaluate(
        address: "203.0.113.10",
        lookupConsented: false,
        response: nil
    )
    try expect(notQueried.state == .warning, "reputation lookup requires explicit consent")
    try expect(notQueried.actions.count == 4, "reputation card offers one query and three reports")

    let cleanAssessment = NodeReputationAssessment.evaluate(
        address: "203.0.113.10",
        lookupConsented: true,
        response: cleanReputation
    )
    try expect(cleanAssessment.state == .passed, "clean public signals are informational pass")
    try expect(cleanAssessment.actions.count == 3, "queried result keeps three cross-check reports")
}

do {
    try runTests()
    print("ClaudeMacGuard self-test: PASS")
} catch {
    fputs("ClaudeMacGuard self-test: FAIL — \(error)\n", stderr)
    exit(1)
}
