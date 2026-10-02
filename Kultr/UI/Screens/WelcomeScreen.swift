import SwiftUI
import UniformTypeIdentifiers

private enum WelcomeStep: Int {
    case hello, choice, server, folders, tour
}

/**
 * The first start: a welcome, then where the music is (a Navidrome server, or
 * folders on this iPhone), then a short tour of what Kultr does.
 *
 * Also shown, without the welcome and the tour, when every library has been
 * signed out of: [returning] starts at the choice and finishes once a library
 * is in use.
 */
struct WelcomeFlow: View {
    @Environment(\.kultr) private var theme
    let returning: Bool
    let onFinished: () -> Void
    @State private var step: WelcomeStep
    @State private var forward = true
    @State private var local = false

    init(returning: Bool, onFinished: @escaping () -> Void) {
        self.returning = returning
        self.onFinished = onFinished
        _step = State(initialValue: returning ? .choice : .hello)
    }

    var body: some View {
        ZStack {
            PlainBackdrop()
            Group {
                switch step {
                case .hello: Hello { go(.choice) }
                case .choice:
                    Choice(
                        returning: returning,
                        onServer: { go(.server) },
                        onLocal: { go(.folders) },
                        onBack: returning ? nil : { go(.hello) },
                        onSaved: onFinished
                    )
                case .server:
                    LoginScreen(onCancel: { go(.choice) }, onDone: {
                        local = false
                        ready()
                    })
                case .folders:
                    Folders(onBack: { go(.choice) }, onDone: {
                        AppGraph.shared.auth.useLocalLibrary()
                        AppGraph.shared.sync.start(.full, quiet: true)
                        local = true
                        ready()
                    })
                case .tour: Tour(local: local, onDone: onFinished)
                }
            }
            .id(step)
            .transition(
                .asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                )
            )
        }
    }

    private func go(_ next: WelcomeStep) {
        forward = next.rawValue > step.rawValue
        withAnimation(theme.spring ?? .linear(duration: 0)) { step = next }
    }

    private func ready() {
        if returning { onFinished() } else { go(.tour) }
    }
}

/** A page of the welcome: centred, readable width, scrolling when the text is large. */
private struct WelcomePage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 18) { content }
                .frame(maxWidth: 460)
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct Hello: View {
    @Environment(\.kultr) private var theme
    let onNext: () -> Void

    var body: some View {
        let c = theme.colors
        VStack(spacing: 0) {
            Spacer()
            Image("KultrLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
            Text("Welcome to Kultr")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(c.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 28)
            Text("Your music, mixed the way a DJ would mix it. From your own Navidrome server, or straight from this iPhone.")
                .font(.system(size: 17))
                .foregroundStyle(c.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 12)
            Spacer()
            WideGlassButton(title: "Get started", icon: "arrow.right", prominent: true, action: onNext)
                .frame(maxWidth: 420)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }
}

private struct Choice: View {
    @Environment(\.kultr) private var theme
    let returning: Bool
    let onServer: () -> Void
    let onLocal: () -> Void
    let onBack: (() -> Void)?
    let onSaved: () -> Void

    var body: some View {
        let c = theme.colors
        let auth = AppGraph.shared.auth
        WelcomePage {
            Text("Where is your music?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(c.ink)
                .multilineTextAlignment(.center)
            Text("You can add the other one later, in Settings.")
                .font(.system(size: 15))
                .foregroundStyle(c.ink2)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                ChoiceCard(
                    icon: "server.rack",
                    title: "On my Navidrome server",
                    text: "Sign in, and Kultr keeps a copy of your library on this iPhone, so browsing is instant and works offline. Plays are counted on your server.",
                    action: onServer
                )
                ChoiceCard(
                    icon: "iphone",
                    title: "On this iPhone",
                    text: "Choose the folders your music is in, in Files. No server, no account: Kultr plays your files, with their covers, albums and artists.",
                    action: onLocal
                )
            }
            .padding(.top, 8)
            let saved = auth.profiles.filter { $0.usable && $0.enabled }
            if returning && !saved.isEmpty {
                Text("Or go back to")
                    .font(KFont.labelLarge)
                    .foregroundStyle(c.ink3)
                    .padding(.top, 12)
                ForEach(saved) { profile in
                    Pill(profile.label, icon: profile.isLocal ? "iphone" : "server.rack") {
                        if auth.switchTo(profile.id) { onSaved() }
                    }
                }
            }
            if let onBack {
                Button("Back", action: onBack)
                    .font(KFont.labelLarge)
                    .foregroundStyle(c.ink2)
                    .padding(.top, 8)
            }
        }
    }
}

private struct ChoiceCard: View {
    @Environment(\.kultr) private var theme
    let icon: String
    let title: String
    let text: String
    let action: () -> Void

    var body: some View {
        let c = theme.colors
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(c.accent)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(c.accentSoft))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(c.ink)
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundStyle(c.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.ink3)
                    .padding(.top, 14)
            }
            .padding(16)
            .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle())
        .kultrGlass(shape, interactive: true, shadow: false)
    }
}

private struct Folders: View {
    @Environment(\.kultr) private var theme
    let onBack: () -> Void
    let onDone: () -> Void

    var body: some View {
        let c = theme.colors
        let folders = AppGraph.shared.local.folders
        WelcomePage {
            Image(systemName: "folder.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(c.accent)
                .frame(width: 72, height: 72)
                .background(Circle().fill(c.accentSoft))
            Text("Choose your music folders")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(c.ink)
                .multilineTextAlignment(.center)
            Text("Pick the folders your music is in: on this iPhone, in iCloud Drive or on a drive you plug in. Kultr gets access to those folders and nothing else, and finds new music in them on its own.")
                .font(.system(size: 15))
                .foregroundStyle(c.ink2)
                .multilineTextAlignment(.center)
            MusicFolders()
                .padding(16)
                .kultrGlass(RoundedRectangle(cornerRadius: 22, style: .continuous), shadow: false)
                .padding(.top, 8)
            HStack(spacing: 10) {
                WideGlassButton(title: "Back", icon: "chevron.left", prominent: false, action: onBack)
                WideGlassButton(title: "Continue", icon: "arrow.right", prominent: true, enabled: !folders.isEmpty, action: onDone)
            }
            .padding(.top, 8)
        }
    }
}

private struct Feature: Identifiable {
    let icon: String
    let title: String
    let text: String
    var id: String { title }
}

private struct Tour: View {
    @Environment(\.kultr) private var theme
    let local: Bool
    let onDone: () -> Void
    @State private var page = 0

    private var features: [Feature] {
        var list = [
            Feature(icon: "sparkles", title: "Mixes like a DJ", text: "InjeKt measures each track's tempo, key and structure, then blends one into the next on the beat. Prefer it simple? Crossfade, gapless or a clean cut, in Settings."),
            Feature(icon: "hand.draw", title: "Glass you can slide", text: "Touch the tab bar and slide your finger along it. Swipe sideways through your library, and pull the player down to close it."),
            Feature(icon: "hand.tap", title: "Touch and hold", text: "Touch and hold a track, an album or an artist to play it next, queue it, favourite it or add it to a playlist. Swipe a track to play it next or queue it."),
        ]
        list.append(local
            ? Feature(icon: "rectangle.on.rectangle", title: "On your Home Screen", text: "Add the Kultr widget to your Home Screen or Lock Screen: what's playing, with play, pause and skip. Control Center and headphones work too.")
            : Feature(icon: "arrow.down.circle", title: "Take it offline", text: "Download albums, playlists or your whole library, and they play without a connection. Plays made offline reach your server later."))
        list.append(Feature(icon: "paintpalette", title: "Make it yours", text: "Choose the shelves on your Home page, colours taken from your artwork, light or dark. It's all in Settings."))
        return list
    }

    var body: some View {
        let c = theme.colors
        let list = features
        let last = page == list.count - 1
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onDone)
                    .font(KFont.labelLarge)
                    .foregroundStyle(c.ink2)
                    .opacity(last ? 0 : 1)
                    .disabled(last)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            TabView(selection: $page) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, feature in
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: feature.icon)
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(c.accent)
                            .frame(width: 112, height: 112)
                            .kultrGlass(Circle(), tint: c.accent.opacity(0.25), shadow: false)
                        Text(feature.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(c.ink)
                            .multilineTextAlignment(.center)
                        Text(feature.text)
                            .font(.system(size: 17))
                            .foregroundStyle(c.ink2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 8) {
                ForEach(0..<list.count, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? c.accent : c.ink4)
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .animation(theme.spring, value: page)
            .padding(.bottom, 20)
            WideGlassButton(title: last ? "Start listening" : "Next", icon: last ? "play.fill" : "arrow.right", prominent: true) {
                if last {
                    onDone()
                } else {
                    withAnimation(theme.spring ?? .linear(duration: 0)) { page += 1 }
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// ------------------------------------------------------------ music folders --

/**
 * The chosen music folders, each with a way to stop using it, and a button
 * that opens the Files folder picker for another.
 */
struct MusicFolders: View {
    @Environment(\.kultr) private var theme
    var onChanged: () -> Void = {}
    @State private var picking = false

    var body: some View {
        let c = theme.colors
        let library = AppGraph.shared.local
        VStack(alignment: .leading, spacing: 10) {
            ForEach(library.folders) { folder in
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(c.accent)
                    Text(folder.name)
                        .font(.system(size: 16))
                        .foregroundStyle(c.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        library.removeFolder(folder)
                        onChanged()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(c.ink3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop using \(folder.name)")
                }
            }
            Pill(library.folders.isEmpty ? "Choose a folder" : "Add another folder", icon: "folder.badge.plus", accent: library.folders.isEmpty) {
                picking = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .musicFolderPicker(isPresented: $picking, onAdded: { _ in onChanged() })
    }
}

extension View {
    /** The Files folder picker; a folder picked there is kept as a music folder. */
    func musicFolderPicker(isPresented: Binding<Bool>, onAdded: @escaping (LocalFolder) -> Void) -> some View {
        fileImporter(isPresented: isPresented, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            let graph = AppGraph.shared
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if let folder = graph.local.addFolder(url) {
                    onAdded(folder)
                } else {
                    graph.messages.error("Kultr was not given access to that folder.")
                }
            case .failure(let error):
                graph.messages.error("Could not open that folder: \(error.localizedDescription)")
            }
        }
    }
}
