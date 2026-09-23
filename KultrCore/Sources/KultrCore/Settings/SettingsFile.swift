import Foundation

/**
 * Settings backup — moving your setup to another phone, or between Kultr on
 * the web, Android and iOS. The file format is the web client's.
 *
 * Deliberately *not* included: usernames, passwords or anything else that could
 * sign someone in. A settings file is the kind of thing people paste into an
 * issue or drop in a shared folder without thinking twice, so credentials are
 * kept out of it by construction.
 */
enum SettingsFile {
    static let kind = "kultr.settings"
    static let version = 1

    /** Keys that are about *this* device, so restoring them elsewhere is wrong. */
    private static let deviceLocalKeys: Set<String> = ["hasSeenWelcome", "streamCacheMb", "offlineWifiOnly"]

    /** Lists whose length is fixed by the app rather than chosen by the person. */
    private static let fixedLengthKeys: Set<String> = ["eqGains"]

    /** Never let anything credential-shaped through, whatever the file claims. */
    private static let forbidden = try! NSRegularExpression(
        pattern: "pass|secret|token|credential|server|username|auth",
        options: [.caseInsensitive]
    )

    private static func isForbidden(_ key: String) -> Bool {
        forbidden.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
    }

    struct ExportedServer: Hashable {
        let label: String
        let serverUrl: String
        let authMode: AuthMode
    }

    struct ImportResult {
        let settings: Settings
        let applied: [String]
        /** Keys in the file that were rejected, with the reason. */
        let skipped: [(key: String, reason: String)]
        /** Servers found in the file, scrubbed of anything credential-shaped. */
        let servers: [ExportedServer]
    }

    struct InvalidFileError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func jsonObject(of settings: Settings) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(settings),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    static func export(
        _ settings: Settings,
        appVersion: String,
        exportedAt: String,
        servers: [ExportedServer]? = nil
    ) -> String {
        let all = jsonObject(of: settings)
        let exported = all.filter { !deviceLocalKeys.contains($0.key) && !isForbidden($0.key) }
        var root: [String: Any] = [
            "kind": kind,
            "version": version,
            "exportedAt": exportedAt,
            "app": "Kultr iOS \(appVersion)",
            "settings": exported,
        ]
        if let servers {
            // Rebuilt field by field, so a profile growing a new property
            // later cannot quietly start appearing in exports.
            root["servers"] = servers.map { server -> [String: Any] in
                [
                    "label": server.label,
                    "serverUrl": server.serverUrl,
                    "authMode": server.authMode == .plain ? "plain" : "token",
                ]
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    /**
     * Validate a settings file against [current]. Every key has to exist in
     * Kultr and carry the same *type* as ours, so a hand-edited or hostile
     * file cannot inject anything: unknown keys, type mismatches, values we do
     * not understand and anything credential-shaped are dropped, not trusted.
     */
    static func importFile(_ text: String, current: Settings) throws -> ImportResult {
        guard let data = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let root = parsed as? [String: Any]
        else { throw InvalidFileError(message: "That file is not a Kultr settings export.") }

        guard (root["kind"] as? String) == kind else {
            throw InvalidFileError(message: "That file is not a Kultr settings export.")
        }
        guard let incoming = root["settings"] as? [String: Any] else {
            throw InvalidFileError(message: "The file has no settings in it.")
        }

        let defaults = jsonObject(of: Settings())
        var working = jsonObject(of: current)
        var result = current
        var applied: [String] = []
        var skipped: [(key: String, reason: String)] = []

        for key in incoming.keys.sorted() {
            let value = incoming[key]!
            guard let expected = defaults[key] else {
                skipped.append((key, "not a setting Kultr for iOS has"))
                continue
            }
            if isForbidden(key) {
                skipped.append((key, "credentials are never imported"))
                continue
            }
            if deviceLocalKeys.contains(key) {
                skipped.append((key, "specific to the device it was exported from"))
                continue
            }
            if !sameShape(expected, value) {
                skipped.append((key, "wrong type"))
                continue
            }
            var candidate = value
            if fixedLengthKeys.contains(key), let list = value as? [Any], let expectedList = expected as? [Any] {
                candidate = Array(list.prefix(expectedList.count))
            }
            var next = working
            next[key] = candidate
            guard let decoded = decode(next), understood(decoded, key: key, candidate: candidate) else {
                skipped.append((key, "value not understood"))
                continue
            }
            working = next
            result = decoded
            applied.append(key)
        }

        let servers = readServers(root["servers"])
        if applied.isEmpty && servers.isEmpty {
            throw InvalidFileError(message: "Nothing in that file could be applied.")
        }
        return ImportResult(settings: result, applied: applied, skipped: skipped, servers: servers)
    }

    private static func decode(_ object: [String: Any]) -> Settings? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: data)
    }

    /**
     * Decoding is forgiving and falls back to defaults, so a value counts as
     * understood only if it survives the round trip unchanged — an unknown
     * theme name, say, would silently turn into the default otherwise.
     */
    private static func understood(_ decoded: Settings, key: String, candidate: Any) -> Bool {
        guard let roundTrip = jsonObject(of: decoded)[key] else { return false }
        return (roundTrip as AnyObject).isEqual(candidate as AnyObject)
    }

    static func kindOf(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if value is [String: Any] { return "object" }
        if value is [Any] { return "array" }
        if value is String { return "string" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "boolean" : "number"
        }
        return "string"
    }

    private static func sameShape(_ expected: Any, _ value: Any) -> Bool {
        let kind = kindOf(expected)
        if kind != kindOf(value) { return false }
        if kind == "number" {
            guard let number = value as? NSNumber, number.doubleValue.isFinite else { return false }
        }
        if let expectedList = expected as? [Any], let list = value as? [Any] {
            // An empty default says nothing about its element type, so those are
            // taken to be lists of ids — which is what all of them currently are.
            let elementKind = expectedList.first.map(kindOf) ?? "string"
            return list.allSatisfy { kindOf($0) == elementKind }
        }
        return true
    }

    private static func readServers(_ input: Any?) -> [ExportedServer] {
        guard let list = input as? [Any] else { return [] }
        return list.compactMap { entry in
            guard let record = entry as? [String: Any], let url = record["serverUrl"] as? String else { return nil }
            let label = record["label"] as? String ?? ""
            let mode: AuthMode = (record["authMode"] as? String) == "plain" ? .plain : .token
            return ExportedServer(label: label, serverUrl: url, authMode: mode)
        }
    }
}
