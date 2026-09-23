import Foundation

/*
 * Decoding that forgives. Navidrome omits empty fields instead of sending
 * nulls, and other Subsonic servers are looser still — ids as numbers,
 * numbers as strings, a single object where a list was expected. A value
 * that does not fit is treated as absent rather than failing the response.
 */

/** A coding key made from any string, for walking JSON by name. */
struct AnyKey: CodingKey, Hashable, ExpressibleByStringLiteral {
    let stringValue: String
    let intValue: Int?

    init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    init(stringLiteral value: String) {
        self.init(value)
    }
}

extension KeyedDecodingContainer {
    func string(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value.isFinite ? String(value) : nil }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return String(value) }
        return nil
    }

    func int(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value.isFinite && abs(value) < 9e15 ? Int(value) : nil
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if let number = Int(trimmed) { return number }
            if let number = Double(trimmed), number.isFinite, abs(number) < 9e15 { return Int(number) }
        }
        return nil
    }

    func int64(_ key: Key) -> Int64? {
        int(key).map { Int64($0) }
    }

    func double(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value.isFinite ? value : nil }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            guard let number = Double(value.trimmingCharacters(in: .whitespaces)), number.isFinite else { return nil }
            return number
        }
        return nil
    }

    func bool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    func object<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }

    /** A list, skipping elements that cannot be read; nil when the key is absent. */
    func list<T: Decodable>(_ type: T.Type, _ key: Key) -> [T]? {
        guard contains(key) else { return nil }
        if (try? decodeNil(forKey: key)) == true { return nil }
        return (try? decode(LossyList<T>.self, forKey: key))?.items
    }
}

/**
 * A JSON array whose unreadable elements are dropped. A single object in
 * place of the array is read as a one-element list.
 */
struct LossyList<Element: Decodable>: Decodable {
    var items: [Element]

    init(items: [Element]) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var out: [Element] = []
            if let count = array.count { out.reserveCapacity(count) }
            while !array.isAtEnd {
                if (try? array.decodeNil()) == true { continue }
                guard let element = try? array.decode(LossyElement<Element>.self) else { break }
                if let value = element.value { out.append(value) }
            }
            items = out
        } else if let single = try? Element(from: decoder) {
            items = [single]
        } else {
            items = []
        }
    }
}

private struct LossyElement<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/** Decodes to nothing, for calls whose answer is just "ok". */
struct EmptyPayload: Decodable {
    init() {}

    init(from decoder: Decoder) throws {}
}
