import Foundation

public enum ProbeParsers {
    public static func firstIPv4(in text: String) -> String? {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .first(where: { IPv4Policy.integer(from: $0) != nil })
    }

    public static func curlRemoteIP(in text: String) -> String? {
        guard let range = text.range(of: "remote_ip=") else { return nil }
        let suffix = text[range.upperBound...]
        return suffix.prefix(while: { !$0.isWhitespace }).description
    }

    public static func tlsIssuer(in text: String) -> String? {
        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine)
            guard let range = line.range(
                of: "issuer:",
                options: [.caseInsensitive, .literal]
            ) else { continue }
            return line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    public static func looksLikeInterceptingIssuer(_ issuer: String) -> Bool {
        let lowered = issuer.lowercased()
        return ["charles", "mitm", "fiddler", "zscaler", "clash", "surge", "proxy"]
            .contains(where: lowered.contains)
    }

    public static func codeSignField(_ field: String, in text: String) -> String? {
        let prefix = "\(field)="
        return text
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count)
            .description
    }
}
