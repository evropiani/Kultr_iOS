import Foundation

/**
 * Kultr's own text in the iPhone's language. KultrCore writes English; the app
 * sets [lookup] once at start to its translations (tests keep English). In a
 * line with values, %@ marks each one, or %1$@, %2$@ when a language puts them
 * in another order.
 */
enum Words {
    static var lookup: (String) -> String = { $0 }

    static func t(_ key: String, _ values: String...) -> String {
        var text = lookup(key)
        for (index, value) in values.enumerated() {
            let numbered = "%\(index + 1)$@"
            if text.contains(numbered) {
                text = text.replacingOccurrences(of: numbered, with: value)
            } else if let range = text.range(of: "%@") {
                text.replaceSubrange(range, with: value)
            }
        }
        return text
    }
}
