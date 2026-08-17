import Foundation

public struct LaunchGateDecision: Sendable, Equatable {
    public let isReady: Bool
    public let summary: String
    public let blockingReasons: [String]

    public init(isReady: Bool, summary: String, blockingReasons: [String]) {
        self.isReady = isReady
        self.summary = summary
        self.blockingReasons = blockingReasons
    }
}

public enum LaunchGate {
    public static let requiredCheckIDs = [
        "exit-verification",
        "proxy-tunnel",
        "ipv6",
        "tls",
        "claude-app"
    ]

    public static func evaluate(_ snapshot: SecuritySnapshot) -> LaunchGateDecision {
        let checksByID = Dictionary(uniqueKeysWithValues: snapshot.checks.map { ($0.id, $0) })
        var reasons: [String] = []

        for id in requiredCheckIDs {
            guard let check = checksByID[id] else {
                reasons.append("缺少必需检查：\(displayName(for: id))")
                continue
            }
            guard check.state == .passed else {
                reasons.append("\(check.title)：\(check.summary)")
                continue
            }
        }

        if reasons.isEmpty {
            return LaunchGateDecision(
                isReady: true,
                summary: "启动所需的本地网络条件均已通过",
                blockingReasons: []
            )
        }

        return LaunchGateDecision(
            isReady: false,
            summary: "Claude 未达到启动条件",
            blockingReasons: reasons
        )
    }

    private static func displayName(for id: String) -> String {
        switch id {
        case "exit-verification": "出口验证"
        case "proxy-tunnel": "代理 / TUN"
        case "ipv6": "IPv6 可达性"
        case "tls": "TLS"
        case "claude-app": "Claude.app"
        default: id
        }
    }
}
