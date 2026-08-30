import Foundation

public struct NodeReputationResponse: Decodable, Sendable, Equatable {
    public let ip: String
    public let reverse: String?
    public let asNumber: String?
    public let asName: String?
    public let countryCode: String?
    public let country: String?
    public let usage: Usage
    public let reputation: Reputation
    public let recommendations: Recommendations

    public struct Usage: Decodable, Sendable, Equatable {
        public let isTor: Bool
        public let isProxy: Bool
        public let isHosting: Bool
        public let isRoutable: Bool

        private enum CodingKeys: String, CodingKey {
            case isTor = "is_tor"
            case isProxy = "is_proxy"
            case isHosting = "is_hosting"
            case isRoutable = "is_routable"
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            isTor = try values.decodeIfPresent(Bool.self, forKey: .isTor) ?? false
            isProxy = try values.decodeIfPresent(Bool.self, forKey: .isProxy) ?? false
            isHosting = try values.decodeIfPresent(Bool.self, forKey: .isHosting) ?? false
            isRoutable = try values.decodeIfPresent(Bool.self, forKey: .isRoutable) ?? false
        }
    }

    public struct Reputation: Decodable, Sendable, Equatable {
        public let webSpam: Bool
        public let webAttacks: Bool
        public let botnet: Bool
        public let emailSpam: Bool
        public let bruteForce: Bool
        public let ddos: Bool

        private enum CodingKeys: String, CodingKey {
            case webSpam = "web_spam"
            case webAttacks = "web_attacks"
            case botnet
            case emailSpam = "email_spam"
            case bruteForce = "brute_force"
            case ddos
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            webSpam = try values.decodeIfPresent(Bool.self, forKey: .webSpam) ?? false
            webAttacks = try values.decodeIfPresent(Bool.self, forKey: .webAttacks) ?? false
            botnet = try values.decodeIfPresent(Bool.self, forKey: .botnet) ?? false
            emailSpam = try values.decodeIfPresent(Bool.self, forKey: .emailSpam) ?? false
            bruteForce = try values.decodeIfPresent(Bool.self, forKey: .bruteForce) ?? false
            ddos = try values.decodeIfPresent(Bool.self, forKey: .ddos) ?? false
        }

        public var activeLabels: [String] {
            var labels: [String] = []
            if webSpam { labels.append("网页垃圾信息") }
            if webAttacks { labels.append("网页攻击") }
            if botnet { labels.append("僵尸网络") }
            if emailSpam { labels.append("邮件垃圾信息") }
            if bruteForce { labels.append("暴力尝试") }
            if ddos { labels.append("DDoS") }
            return labels
        }
    }

    public struct Recommendations: Decodable, Sendable, Equatable {
        public let blockTraffic: Bool

        private enum CodingKeys: String, CodingKey {
            case blockTraffic = "block_traffic"
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            blockTraffic = try values.decodeIfPresent(Bool.self, forKey: .blockTraffic) ?? false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case ip
        case reverse
        case asNumber = "as_number"
        case asName = "as_name"
        case countryCode = "country_code"
        case country
        case usage
        case reputation
        case recommendations
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ip = try values.decode(String.self, forKey: .ip)
        reverse = try values.decodeIfPresent(String.self, forKey: .reverse)
        if let stringValue = try? values.decodeIfPresent(String.self, forKey: .asNumber) {
            asNumber = stringValue
        } else if let intValue = try? values.decodeIfPresent(Int.self, forKey: .asNumber) {
            asNumber = String(intValue)
        } else {
            asNumber = nil
        }
        asName = try values.decodeIfPresent(String.self, forKey: .asName)
        countryCode = try values.decodeIfPresent(String.self, forKey: .countryCode)
        country = try values.decodeIfPresent(String.self, forKey: .country)
        usage = try values.decode(Usage.self, forKey: .usage)
        reputation = try values.decode(Reputation.self, forKey: .reputation)
        recommendations = try values.decode(Recommendations.self, forKey: .recommendations)
    }
}

public enum NodeReputationAssessment {
    public static func evaluate(
        address: String?,
        lookupConsented: Bool,
        response: NodeReputationResponse?
    ) -> CheckResult {
        guard let address else {
            return CheckResult(
                id: "node-reputation",
                title: "节点公开信誉",
                state: .unavailable,
                summary: "出口尚未稳定，无法查询公开信誉",
                details: ["不会向信誉服务发送不确定的 IP。"]
            )
        }

        guard lookupConsented else {
            return CheckResult(
                id: "node-reputation",
                title: "节点公开信誉",
                state: .warning,
                summary: "尚未查询公开风险记录",
                details: [
                    "查询前会征得同意，并把当前出口 IP 发送给 reputation.noc.org。",
                    "结果只能作为线索，不能证明节点运营者可信。"
                ],
                actions: [.queryPublicReputation(address)] + reportActions(for: address)
            )
        }

        guard let response, response.ip == address else {
            return CheckResult(
                id: "node-reputation",
                title: "节点公开信誉",
                state: .unavailable,
                summary: "公开信誉查询暂时不可用",
                details: [
                    "未获得与 \(address) 匹配的结果。",
                    "数据源：reputation.noc.org"
                ],
                actions: [.queryPublicReputation(address)] + reportActions(for: address)
            )
        }

        var details: [String] = []
        let network = [
            response.asNumber.map { "AS\($0)" },
            response.asName
        ].compactMap { $0 }.joined(separator: " · ")
        if !network.isEmpty { details.append("网络归属：\(network)") }
        if let country = response.country, let code = response.countryCode {
            details.append("登记地区：\(country)（\(code)）")
        }
        if let reverse = response.reverse, !reverse.isEmpty {
            details.append("反向域名：\(reverse)")
        }

        var usageLabels: [String] = []
        if response.usage.isHosting { usageLabels.append("机房/托管网络") }
        if response.usage.isProxy { usageLabels.append("已知代理") }
        if response.usage.isTor { usageLabels.append("Tor") }
        if response.usage.isRoutable { usageLabels.append("公网可路由") }
        details.append("网络类型：\(usageLabels.isEmpty ? "未分类" : usageLabels.joined(separator: "、"))")

        let risks = response.reputation.activeLabels
        details.append(risks.isEmpty ? "公开风险信号：未发现" : "公开风险信号：\(risks.joined(separator: "、"))")
        details.append("数据源：reputation.noc.org；本次查询已向其发送 \(address)。")
        details.append("机房或代理属性本身不是恶意证据；共享出口也可能继承其他用户的记录。")

        let hasRisk = !risks.isEmpty || response.usage.isTor || response.recommendations.blockTraffic
        return CheckResult(
            id: "node-reputation",
            title: "节点公开信誉",
            state: hasRisk ? .warning : .passed,
            summary: hasRisk
                ? "公开数据中存在需要留意的信号"
                : "当前公开数据未返回已知攻击信号",
            details: details,
            actions: reportActions(for: address)
        )
    }

    private static func reportActions(for address: String) -> [CheckAction] {
        [
            .openExternalReport(
                name: "Ping0",
                url: "https://ping0.cc/ip/\(address)",
                address: address
            ),
            .openExternalReport(
                name: "ipdata",
                url: "https://ipdata.co/?ip=\(address)",
                address: address
            ),
            .openExternalReport(
                name: "Scamalytics",
                url: "https://scamalytics.com/ip/\(address)",
                address: address
            )
        ]
    }
}
