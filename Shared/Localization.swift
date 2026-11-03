import Foundation

extension String {
    /**
     * This text in the iPhone's language, from Localizable.xcstrings, or as it
     * is when there is no translation. For Kultr's own text that reaches a
     * view as a String: Text("…") looks itself up, Text(someString) doesn't.
     */
    var loc: String { Bundle.main.localizedString(forKey: self, value: self, table: nil) }
}
