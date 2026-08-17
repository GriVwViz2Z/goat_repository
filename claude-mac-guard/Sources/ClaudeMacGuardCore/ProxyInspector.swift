import Darwin
import Foundation
import SystemConfiguration

public struct ProxySnapshot: Sendable, Equatable {
    public let descriptions: [String]
    public let preferredProxyURL: String?
    public let tunnelInterfaces: [String]

    public init(
        descriptions: [String],
        preferredProxyURL: String?,
        tunnelInterfaces: [String]
    ) {
        self.descriptions = descriptions
        self.preferredProxyURL = preferredProxyURL
        self.tunnelInterfaces = tunnelInterfaces
    }

    public var hasSystemProxy: Bool { !descriptions.isEmpty }
    public var hasTunnel: Bool { !tunnelInterfaces.isEmpty }
}

public enum ProxyInspector {
    public static func inspect() -> ProxySnapshot {
        let dictionary = SCDynamicStoreCopyProxies(nil) as NSDictionary? ?? [:]
        var descriptions: [String] = []
        var preferredProxyURL: String?

        func enabled(_ key: CFString) -> Bool {
            (dictionary[key as String] as? NSNumber)?.boolValue == true
        }

        func host(_ key: CFString) -> String? {
            dictionary[key as String] as? String
        }

        func port(_ key: CFString) -> Int? {
            (dictionary[key as String] as? NSNumber)?.intValue
        }

        if enabled(kSCPropNetProxiesHTTPSEnable),
           let value = host(kSCPropNetProxiesHTTPSProxy),
           let number = port(kSCPropNetProxiesHTTPSPort) {
            descriptions.append("HTTPS \(value):\(number)")
            preferredProxyURL = "http://\(value):\(number)"
        }

        if enabled(kSCPropNetProxiesHTTPEnable),
           let value = host(kSCPropNetProxiesHTTPProxy),
           let number = port(kSCPropNetProxiesHTTPPort) {
            descriptions.append("HTTP \(value):\(number)")
            if preferredProxyURL == nil {
                preferredProxyURL = "http://\(value):\(number)"
            }
        }

        if enabled(kSCPropNetProxiesSOCKSEnable),
           let value = host(kSCPropNetProxiesSOCKSProxy),
           let number = port(kSCPropNetProxiesSOCKSPort) {
            descriptions.append("SOCKS \(value):\(number)")
            if preferredProxyURL == nil {
                preferredProxyURL = "socks5h://\(value):\(number)"
            }
        }

        if enabled(kSCPropNetProxiesProxyAutoConfigEnable),
           let value = host(kSCPropNetProxiesProxyAutoConfigURLString) {
            descriptions.append("PAC \(value)")
        }

        return ProxySnapshot(
            descriptions: descriptions,
            preferredProxyURL: preferredProxyURL,
            tunnelInterfaces: activeTunnelInterfaces()
        )
    }

    private static func activeTunnelInterfaces() -> [String] {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return [] }
        defer { freeifaddrs(firstAddress) }

        var names = Set<String>()
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let pointer = current {
            let flags = Int32(pointer.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            if isUp, let rawName = pointer.pointee.ifa_name {
                let name = String(cString: rawName)
                if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                    names.insert(name)
                }
            }
            current = pointer.pointee.ifa_next
        }
        return names.sorted()
    }
}
