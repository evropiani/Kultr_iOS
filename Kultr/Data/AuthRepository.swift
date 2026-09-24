import Foundation
import Observation

struct ServerProfile: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var serverUrl: String
    var username: String
    var authMode: AuthMode = .token
    /**
     * A server you keep but are not using right now. Disabled servers stay in
     * the list with their credentials intact; they just cannot be connected to.
     */
    var enabled: Bool = true
    /** Whether a password is saved in the Keychain. False for imported profiles. */
    var hasSecret: Bool = false

    var hasCredentials: Bool { !username.trimmingCharacters(in: .whitespaces).isEmpty && hasSecret }
}

enum Connection: Equatable {
    case idle
    case connecting
    case online(ServerInfo)
    /** Signed in, but the server cannot be reached right now. Offline copies still play. */
    case offline(String)
}

func hostLabel(_ url: String) -> String {
    guard let components = URLComponents(string: url), let host = components.host else { return url }
    if let port = components.port, port != 80, port != 443 { return "\(host):\(port)" }
    return host
}

private func profileId(_ url: String, _ username: String) -> String {
    var trimmed = url
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    return "\(trimmed)#\(username)".lowercased()
}

private func stableSaltFor(_ profileId: String) -> String {
    String(md5Hex("kultr-salt:\(profileId)").prefix(12))
}

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

/** Saved servers, which one is active, and the API client for it. */
@MainActor
@Observable
final class AuthRepository {
    private static let profilesKey = "auth.profiles"
    private static let activeKey = "auth.active"

    private(set) var profiles: [ServerProfile] = []
    private(set) var active: ServerProfile?
    private(set) var client: SubsonicClient?
    private(set) var connection: Connection = .idle

    @ObservationIgnored let session: URLSession
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var listeners: [(ServerProfile?) -> Void] = []

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.httpAdditionalHeaders = ["User-Agent": "Kultr-iOS/\(appVersion)"]
        session = URLSession(configuration: config)
        profiles = loadProfiles()
        if let activeId = UserDefaults.standard.string(forKey: Self.activeKey),
           let profile = profiles.first(where: { $0.id == activeId }), profile.enabled {
            activate(profile, ping: true)
        }
    }

    /** Called whenever the active server changes (including to none). */
    func observeActive(_ listener: @escaping (ServerProfile?) -> Void) {
        listeners.append(listener)
    }

    private func notify() {
        listeners.forEach { $0(active) }
    }

    private func loadProfiles() -> [ServerProfile] {
        guard let data = UserDefaults.standard.data(forKey: Self.profilesKey) else { return [] }
        return (try? JSONDecoder().decode([ServerProfile].self, from: data)) ?? []
    }

    private func saveProfiles(_ list: [ServerProfile]) {
        profiles = list
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
        }
    }

    private func saveActive(_ id: String?) {
        UserDefaults.standard.set(id, forKey: Self.activeKey)
    }

    private func buildClient(_ profile: ServerProfile) -> SubsonicClient? {
        guard !profile.username.isEmpty, let password = Keychain.get(profile.id) else { return nil }
        return SubsonicClient(
            credentials: Credentials(serverUrl: profile.serverUrl, username: profile.username, password: password, authMode: profile.authMode),
            session: session,
            stableSalt: stableSaltFor(profile.id),
            userAgent: "Kultr-iOS/\(appVersion)"
        )
    }

    /**
     * Make [profile] the active one. The client exists straight away, so the
     * library and downloads work even if the server does not answer.
     */
    private func activate(_ profile: ServerProfile, ping: Bool) {
        let previous = active?.id
        let client = buildClient(profile)
        active = profile
        self.client = client
        saveActive(profile.id)
        if previous != profile.id { notify() }
        guard client != nil else {
            connection = .offline("Sign in again: the saved password could not be read.")
            return
        }
        if ping { refreshConnection() }
    }

    /** Ask the server whether it is there; updates [connection]. */
    func refreshConnection() {
        guard let client else { return }
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            self?.connection = .connecting
            do {
                let info = try await client.ping()
                if !Task.isCancelled { self?.connection = .online(info) }
            } catch {
                if !Task.isCancelled { self?.connection = .offline(describeError(error)) }
            }
        }
    }

    struct LoginInput {
        var serverUrl: String
        var username: String
        var password: String
        var label: String = ""
        var authMode: AuthMode = .token
    }

    /** Check the credentials against the server and, if they work, sign in. Returns an error message on failure. */
    func login(_ input: LoginInput) async -> String? {
        let url = normalizeServerUrl(input.serverUrl)
        if url.isEmpty { return "Enter your server’s address." }
        if !isValidServerUrl(url) { return "“\(input.serverUrl)” is not a valid address." }
        let username = input.username.trimmingCharacters(in: .whitespaces)
        if username.isEmpty { return "Enter your username." }
        let id = profileId(url, username)
        let client = SubsonicClient(
            credentials: Credentials(serverUrl: url, username: username, password: input.password, authMode: input.authMode),
            session: session,
            stableSalt: stableSaltFor(id),
            userAgent: "Kultr-iOS/\(appVersion)"
        )
        connection = .connecting
        do {
            let info = try await client.ping()
            let existing = profiles.first { $0.id == id }
            let label = input.label.trimmingCharacters(in: .whitespaces)
            let saved = Keychain.set(input.password, for: id)
            let profile = ServerProfile(
                id: id,
                label: label.isEmpty ? (existing?.label ?? hostLabel(client.baseUrl)) : label,
                serverUrl: client.baseUrl,
                username: username,
                authMode: input.authMode,
                enabled: true,
                hasSecret: saved
            )
            // Replace the profile, and any credential-less placeholder imported for this address.
            saveProfiles(profiles.filter { $0.id != id && !($0.serverUrl == profile.serverUrl && !$0.hasCredentials) } + [profile])
            let previous = active?.id
            active = profile
            self.client = client
            saveActive(id)
            connection = .online(info)
            if previous != id { notify() }
            return nil
        } catch {
            connection = self.client != nil ? .offline(describeError(error)) : .idle
            return describeError(error)
        }
    }

    @discardableResult
    func switchTo(_ id: String) -> Bool {
        guard let profile = profiles.first(where: { $0.id == id }), profile.enabled, profile.hasCredentials else { return false }
        activate(profile, ping: true)
        return true
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        saveProfiles(profiles.map { profile in
            var copy = profile
            if copy.id == id { copy.enabled = enabled }
            return copy
        })
        if !enabled && active?.id == id { signOut() }
    }

    /** Give a server a new name; an empty name goes back to its address. */
    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        saveProfiles(profiles.map { profile in
            var copy = profile
            if copy.id == id { copy.label = trimmed.isEmpty ? hostLabel(copy.serverUrl) : trimmed }
            return copy
        })
        if let current = active, current.id == id, let updated = profiles.first(where: { $0.id == id }) {
            active = updated
        }
    }

    /** Forget a server entirely. Returns the removed profile so its data can be wiped. */
    @discardableResult
    func remove(_ id: String) -> ServerProfile? {
        guard let profile = profiles.first(where: { $0.id == id }) else { return nil }
        saveProfiles(profiles.filter { $0.id != id })
        Keychain.delete(id)
        if active?.id == id { signOut() }
        return profile
    }

    /** Leave the current server; its profile and library stay for next time. */
    func signOut() {
        pingTask?.cancel()
        let had = active != nil
        active = nil
        client = nil
        connection = .idle
        saveActive(nil)
        if had { notify() }
    }

    /** Servers from a settings file. They arrive without credentials. */
    func importServers(_ servers: [SettingsFile.ExportedServer]) -> Int {
        var added = 0
        var list = profiles
        for server in servers {
            let url = normalizeServerUrl(server.serverUrl)
            if url.isEmpty || list.contains(where: { $0.serverUrl.caseInsensitiveCompare(url) == .orderedSame }) { continue }
            list.append(
                ServerProfile(
                    id: profileId(url, ""),
                    label: server.label.trimmingCharacters(in: .whitespaces).isEmpty ? hostLabel(url) : server.label,
                    serverUrl: url,
                    username: "",
                    authMode: server.authMode
                )
            )
            added += 1
        }
        if added > 0 { saveProfiles(list) }
        return added
    }
}
