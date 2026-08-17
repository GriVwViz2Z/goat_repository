import Foundation

public enum IPv4Policy {
    public static func integer(from address: String) -> UInt32? {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(octet)
        }
        return value
    }

    public static func contains(address: String, cidr: String) -> Bool {
        let pieces = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              let ip = integer(from: address),
              let base = integer(from: String(pieces[0])),
              let prefix = UInt32(pieces[1]),
              prefix <= 32
        else { return false }

        let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
        return (ip & mask) == (base & mask)
    }

    public static func isAllowed(
        _ address: String,
        exact: [String],
        cidrs: [String]
    ) -> Bool {
        exact.contains(address) || cidrs.contains(where: { contains(address: address, cidr: $0) })
    }
}

public enum IPv6ProbeInterpretation: Equatable, Sendable {
    case unreachable
    case fakeIPv4Mapping(String)
    case publicReachability(String)
    case malformed(String)

    public static func interpret(remoteIP: String?, commandSucceeded: Bool) -> Self {
        guard commandSucceeded else { return .unreachable }
        guard let remoteIP, !remoteIP.isEmpty else { return .malformed("missing remote IP") }

        if remoteIP.hasPrefix("::ffff:198.18.") || remoteIP.hasPrefix("::ffff:198.19.") ||
            remoteIP.hasPrefix("198.18.") || remoteIP.hasPrefix("198.19.") {
            return .fakeIPv4Mapping(remoteIP)
        }
        if remoteIP.hasPrefix("::ffff:") {
            return .fakeIPv4Mapping(remoteIP)
        }
        return .publicReachability(remoteIP)
    }
}
