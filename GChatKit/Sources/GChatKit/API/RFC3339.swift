import Foundation

/// Google timestamps are RFC 3339 with zero to nine fractional digits.
public enum RFC3339 {
    public static func date(from string: String) -> Date? {
        var base = string
        var fraction = 0.0
        if let dot = string.firstIndex(of: ".") {
            let rest = string[string.index(after: dot)...]
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            fraction = Double("0." + digits) ?? 0
            base = String(string[..<dot]) + rest.dropFirst(digits.count)
        }
        guard let date = try? Date(base, strategy: .iso8601) else { return nil }
        return date.addingTimeInterval(fraction)
    }

    /// Microsecond precision, UTC. The fraction is truncated, never rounded up.
    public static func string(from date: Date) -> String {
        let interval = date.timeIntervalSinceReferenceDate
        let whole = interval.rounded(.down)
        let micros = min(Int((interval - whole) * 1_000_000), 999_999)
        let base = Date(timeIntervalSinceReferenceDate: whole).formatted(.iso8601)
        let padded = String(repeating: "0", count: 6 - String(micros).count) + String(micros)
        return base.replacingOccurrences(of: "Z", with: ".\(padded)Z")
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = RFC3339.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Not an RFC 3339 timestamp: \(string)")
            }
            return date
        }
        return decoder
    }
}
