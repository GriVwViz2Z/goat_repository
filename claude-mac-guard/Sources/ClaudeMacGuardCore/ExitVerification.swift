import Foundation

public struct ExitSample: Codable, Sendable, Equatable {
    public let provider: String
    public let address: String

    public init(provider: String, address: String) {
        self.provider = provider
        self.address = address
    }
}

public struct ExitMetadata: Codable, Sendable, Equatable {
    public let address: String
    public let city: String?
    public let region: String?
    public let countryCode: String
    public let countryName: String
    public let asn: String
    public let organization: String

    public init(
        address: String,
        city: String? = nil,
        region: String? = nil,
        countryCode: String,
        countryName: String,
        asn: String,
        organization: String
    ) {
        self.address = address
        self.city = city
        self.region = region
        self.countryCode = countryCode.uppercased()
        self.countryName = countryName
        self.asn = Self.normalizedASN(asn)
        self.organization = organization
    }

    public var locationDescription: String {
        [countryName, region, city]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    public static func normalizedASN(_ value: String) -> String {
        let compact = value.uppercased().replacingOccurrences(of: " ", with: "")
        if compact.hasPrefix("AS") { return compact }
        return compact.isEmpty ? compact : "AS\(compact)"
    }
}

public struct ExitVerificationEvidence: Codable, Sendable, Equatable {
    public let requestedSampleCount: Int
    public let samples: [ExitSample]
    public let metadata: ExitMetadata?
    public let explicitProxyURL: String?

    public init(
        requestedSampleCount: Int,
        samples: [ExitSample],
        metadata: ExitMetadata?,
        explicitProxyURL: String?
    ) {
        self.requestedSampleCount = requestedSampleCount
        self.samples = samples
        self.metadata = metadata
        self.explicitProxyURL = explicitProxyURL
    }
}

public enum ExitVerification {
    public static func evaluate(
        evidence: ExitVerificationEvidence,
        policy: MonitorPolicy
    ) -> CheckResult {
        let addresses = evidence.samples.map(\.address)
        let uniqueAddresses = Array(Set(addresses)).sorted()
        var details = evidence.samples.map { "\($0.provider)：\($0.address)" }

        guard evidence.samples.count >= evidence.requestedSampleCount else {
            return CheckResult(
                id: "exit-verification",
                title: "出口验证",
                state: .unavailable,
                summary: "出口采样不完整（\(evidence.samples.count)/\(evidence.requestedSampleCount)）",
                details: details + ["证据不足时不会判定为通过。"]
            )
        }

        guard uniqueAddresses.count == 1, let address = uniqueAddresses.first else {
            return CheckResult(
                id: "exit-verification",
                title: "出口验证",
                state: policy.requireStableExit ? .failed : .warning,
                summary: "采样期间观察到多个出口 IP",
                details: details + ["出口发生轮换或不同查询没有走同一路径。"]
            )
        }

        if policy.requireProxyOrTunnel && evidence.explicitProxyURL == nil {
            return CheckResult(
                id: "exit-verification",
                title: "出口验证",
                state: .failed,
                summary: "出口稳定，但无法确认探测经过显式系统代理",
                details: details + ["未把仅有 TUN 接口当作已确认的代理路径。"]
            )
        }

        if let metadata = evidence.metadata, metadata.address == address {
            details.append("地区：\(metadata.locationDescription)（\(metadata.countryCode)）")
            details.append("网络归属：\(metadata.asn) · \(metadata.organization)")
            details.append("地区与 ASN：由 ipwho.is 查询，仅供参考，不参与可信判定。")
        } else {
            details.append("地区与 ASN：暂时无法查询，仅供参考，不参与可信判定。")
        }
        if let proxyURL = evidence.explicitProxyURL {
            details.append("显式代理路径：\(proxyURL)")
        }
        details.append("地区查询会向 ipwho.is 发送当前出口 IP。")

        let hasIPRules = !policy.allowedExitIPv4.isEmpty || !policy.allowedExitCIDRs.isEmpty

        guard hasIPRules else {
            return CheckResult(
                id: "exit-verification",
                title: "出口验证",
                state: .warning,
                summary: "已识别稳定出口 \(address)，尚未建立已确认出口基线",
                details: details + ["只有你确认它确实来自自己选择的节点后，这个 IP 才会加入本机已确认列表。"],
                actions: [.confirmExitIPv4(address)]
            )
        }

        if !IPv4Policy.isAllowed(
            address,
            exact: policy.allowedExitIPv4,
            cidrs: policy.allowedExitCIDRs
        ) {
            return CheckResult(
                id: "exit-verification",
                title: "出口验证",
                state: .failed,
                summary: "当前出口 \(address) 不在本机已确认列表",
                details: details + ["如果这是你刚刚主动切换的 Shadowrocket 节点，可以核对来源后再确认。"],
                actions: [.confirmExitIPv4(address)]
            )
        }

        return CheckResult(
            id: "exit-verification",
            title: "出口验证",
            state: .passed,
            summary: "稳定出口 \(address) 已在本机确认列表",
            details: details + ["这只表示出口与本机策略一致，不代表平台账号安全。"]
        )
    }
}

public struct IPWhoResponse: Decodable {
    let ip: String?
    let success: Bool?
    let city: String?
    let region: String?
    let countryCode: String?
    let country: String?
    let connection: Connection?

    struct Connection: Decodable {
        let asn: Int?
        let organization: String?

        enum CodingKeys: String, CodingKey {
            case asn
            case organization = "org"
        }
    }

    enum CodingKeys: String, CodingKey {
        case ip
        case success
        case city
        case region
        case countryCode = "country_code"
        case country
        case connection
    }

    public func metadata(expectedAddress: String) -> ExitMetadata? {
        guard success == true,
              ip == expectedAddress,
              let countryCode, !countryCode.isEmpty,
              let country, !country.isEmpty,
              let connection,
              let asn = connection.asn,
              let organization = connection.organization, !organization.isEmpty
        else { return nil }

        return ExitMetadata(
            address: expectedAddress,
            city: city,
            region: region,
            countryCode: countryCode,
            countryName: country,
            asn: String(asn),
            organization: organization
        )
    }
}
