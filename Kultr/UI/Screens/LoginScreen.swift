import SwiftUI

/**
 * One screen to connect: the server's address, a username and a password.
 * Also used to add a second server, or to sign back in to a saved one.
 */
struct LoginScreen: View {
    @Environment(\.kultr) private var theme
    var prefillUrl = ""
    var prefillUser = ""
    var prefillLabel = ""
    var onCancel: (() -> Void)?
    var onDone: () -> Void = {}

    @State private var url = ""
    @State private var user = ""
    @State private var password = ""
    @State private var label = ""
    @State private var plain = false
    @State private var showPassword = false
    @State private var advanced = false
    @State private var busy = false
    @State private var error: String?
    @State private var filled = false

    var body: some View {
        let c = theme.colors
        let auth = AppGraph.shared.auth
        ZStack {
            PlainBackdrop()
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 24)
                    Image("KultrLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                    Text("Kultr")
                        .font(KFont.headlineLarge)
                        .foregroundStyle(c.ink)
                        .padding(.top, 12)
                    Text("Connect to your Navidrome server. Kultr mirrors your library on this phone, crossfades properly and mixes like a DJ.")
                        .font(KFont.bodyMedium)
                        .foregroundStyle(c.ink2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            field("Server address", text: $url, icon: "server.rack", placeholder: "https://music.example.com")
                                .keyboardType(.URL)
                                .textContentType(.URL)
                            field("Username", text: $user, placeholder: "")
                                .textContentType(.username)
                            passwordField
                            Button(advanced ? "Hide advanced options" : "Advanced options") { advanced.toggle() }
                                .font(KFont.labelLarge)
                                .foregroundStyle(c.accent)
                            if advanced {
                                field("Name for this server (optional)", text: $label, placeholder: "")
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Plain password").foregroundStyle(c.ink)
                                        Text("Only for servers or proxies that reject token authentication. Use HTTPS.")
                                            .font(KFont.bodySmall)
                                            .foregroundStyle(c.ink3)
                                    }
                                    Spacer()
                                    KultrSwitch(isOn: plain) { plain = $0 }
                                }
                            }
                            if let error {
                                Text(error).font(KFont.bodyMedium).foregroundStyle(c.danger)
                            }
                            HStack(spacing: 10) {
                                if let onCancel {
                                    WideGlassButton(title: "Cancel", icon: "xmark", prominent: false, action: onCancel)
                                }
                                WideGlassButton(
                                    title: busy ? "Connecting…" : "Connect",
                                    icon: busy ? "hourglass" : "arrow.right.circle.fill",
                                    prominent: true,
                                    enabled: !busy && !url.trimmingCharacters(in: .whitespaces).isEmpty && !user.trimmingCharacters(in: .whitespaces).isEmpty
                                ) { submit() }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: 480)
                    let saved = auth.profiles.filter { $0.hasCredentials && $0.enabled }
                    if !saved.isEmpty && onCancel == nil {
                        Text("Or pick a saved server")
                            .font(KFont.labelLarge)
                            .foregroundStyle(c.ink3)
                            .padding(.top, 24)
                            .padding(.bottom, 8)
                        ForEach(saved) { profile in
                            Pill("\(profile.label) · \(profile.username)") {
                                if auth.switchTo(profile.id) { onDone() }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Text("Your password stays on this phone, sealed in the iOS Keychain, and is only ever sent to your own server.")
                        .font(KFont.bodySmall)
                        .foregroundStyle(c.ink3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .padding(.top, 32)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if !filled {
                filled = true
                url = prefillUrl
                user = prefillUser
                label = prefillLabel
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, icon: String? = nil, placeholder: String) -> some View {
        let c = theme.colors
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(KFont.labelMedium).foregroundStyle(c.ink2)
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).foregroundStyle(c.ink3) }
                TextField("", text: text, prompt: Text(placeholder).foregroundStyle(c.ink4))
                    .foregroundStyle(c.ink)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: theme.radii.xs, style: .continuous).strokeBorder(c.edge, lineWidth: 1))
        }
    }

    private var passwordField: some View {
        let c = theme.colors
        return VStack(alignment: .leading, spacing: 4) {
            Text("Password").font(KFont.labelMedium).foregroundStyle(c.ink2)
            HStack(spacing: 10) {
                Group {
                    if showPassword {
                        TextField("", text: $password)
                    } else {
                        SecureField("", text: $password)
                    }
                }
                .foregroundStyle(c.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit { submit() }
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(c.ink3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: theme.radii.xs, style: .continuous).strokeBorder(c.edge, lineWidth: 1))
        }
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        error = nil
        let input = AuthRepository.LoginInput(serverUrl: url, username: user, password: password, label: label, authMode: plain ? .plain : .token)
        Task {
            let result = await AppGraph.shared.auth.login(input)
            busy = false
            if let result {
                error = result
            } else {
                AppGraph.shared.sync.startFirstSyncIfNeeded()
                onDone()
            }
        }
    }
}
