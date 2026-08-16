import Foundation

public enum CheckState: String, Codable, Sendable {
    case passed
    case warning
    case failed
    case unavailable
}

public enum CheckAction: Codable, Sendable, Equatable {
    case confirmExitIPv4(String)
    case queryPublicReputation(String)
    case openExternalReport(name: String, url: String, address: String)
}

public struct CheckResult: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let state: CheckState
    public let summary: String
    public let details: [String]
    public let actions: [CheckAction]

    public init(
        id: String,
        title: String,
        state: CheckState,
        summary: String,
        details: [String] = [],
        actions: [CheckAction] = []
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.summary = summary
        self.details = details
        self.actions = actions
    }
}

public struct SecuritySnapshot: Codable, Sendable, Equatable {
    public let observedAt: Date
    public let checks: [CheckResult]
    public let blockingActive: Bool

    public init(observedAt: Date = Date(), checks: [CheckResult], blockingActive: Bool = false) {
        self.observedAt = observedAt
        self.checks = checks
        self.blockingActive = blockingActive
    }

    public var overallState: CheckState {
        if checks.contains(where: { $0.state == .failed }) { return .failed }
        if checks.contains(where: { $0.state == .warning || $0.state == .unavailable }) {
            return .warning
        }
        return .passed
    }
}

public struct MonitorPolicy: Codable, Sendable, Equatable {
    public var allowedExitIPv4: [String]
    public var allowedExitCIDRs: [String]
    public var requireProxyOrTunnel: Bool
    public var requireStableExit: Bool
    public var exitSampleCount: Int
    public var expectedClaudeBundleIdentifier: String
    public var expectedClaudeTeamIdentifier: String
    public var claudeAppPath: String
    public var apiHost: String

    public init(
        allowedExitIPv4: [String] = [],
        allowedExitCIDRs: [String] = [],
        requireProxyOrTunnel: Bool = true,
        requireStableExit: Bool = true,
        exitSampleCount: Int = 3,
        expectedClaudeBundleIdentifier: String = "com.anthropic.claudefordesktop",
        expectedClaudeTeamIdentifier: String = "Q6L2SF6YDW",
        claudeAppPath: String = "/Applications/Claude.app",
        apiHost: String = "api.anthropic.com"
    ) {
        self.allowedExitIPv4 = allowedExitIPv4
        self.allowedExitCIDRs = allowedExitCIDRs
        self.requireProxyOrTunnel = requireProxyOrTunnel
        self.requireStableExit = requireStableExit
        self.exitSampleCount = min(max(exitSampleCount, 3), 5)
        self.expectedClaudeBundleIdentifier = expectedClaudeBundleIdentifier
        self.expectedClaudeTeamIdentifier = expectedClaudeTeamIdentifier
        self.claudeAppPath = claudeAppPath
        self.apiHost = apiHost
    }

    private enum CodingKeys: String, CodingKey {
        case allowedExitIPv4
        case allowedExitCIDRs
        case requireProxyOrTunnel
        case requireStableExit
        case exitSampleCount
        case expectedClaudeBundleIdentifier
        case expectedClaudeTeamIdentifier
        case claudeAppPath
        case apiHost
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            allowedExitIPv4: try values.decodeIfPresent([String].self, forKey: .allowedExitIPv4) ?? [],
            allowedExitCIDRs: try values.decodeIfPresent([String].self, forKey: .allowedExitCIDRs) ?? [],
            requireProxyOrTunnel: try values.decodeIfPresent(Bool.self, forKey: .requireProxyOrTunnel) ?? true,
            requireStableExit: try values.decodeIfPresent(Bool.self, forKey: .requireStableExit) ?? true,
            exitSampleCount: try values.decodeIfPresent(Int.self, forKey: .exitSampleCount) ?? 3,
            expectedClaudeBundleIdentifier: try values.decodeIfPresent(String.self, forKey: .expectedClaudeBundleIdentifier) ?? "com.anthropic.claudefordesktop",
            expectedClaudeTeamIdentifier: try values.decodeIfPresent(String.self, forKey: .expectedClaudeTeamIdentifier) ?? "Q6L2SF6YDW",
            claudeAppPath: try values.decodeIfPresent(String.self, forKey: .claudeAppPath) ?? "/Applications/Claude.app",
            apiHost: try values.decodeIfPresent(String.self, forKey: .apiHost) ?? "api.anthropic.com"
        )
    }
}

public enum PolicyLoader {
    public static let defaultPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/claude-mac-guard/policy.json")

    public static func load(from url: URL = defaultPath) -> MonitorPolicy {
        guard let data = try? Data(contentsOf: url),
              let policy = try? JSONDecoder().decode(MonitorPolicy.self, from: data)
        else {
            return MonitorPolicy()
        }
        return policy
    }
}

public enum PolicyStoreError: LocalizedError {
    case invalidIPv4(String)

    public var errorDescription: String? {
        switch self {
        case .invalidIPv4(let address):
            "无法保存无效的 IPv4 地址：\(address)"
        }
    }
}

public enum PolicyStore {
    public static func confirmExitIPv4(
        _ address: String,
        at url: URL = PolicyLoader.defaultPath
    ) throws {
        guard IPv4Policy.integer(from: address) != nil else {
            throw PolicyStoreError.invalidIPv4(address)
        }

        var policy: MonitorPolicy
        if FileManager.default.fileExists(atPath: url.path) {
            policy = try JSONDecoder().decode(MonitorPolicy.self, from: Data(contentsOf: url))
        } else {
            policy = MonitorPolicy()
        }

        if !policy.allowedExitIPv4.contains(address) {
            policy.allowedExitIPv4.append(address)
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(policy).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
