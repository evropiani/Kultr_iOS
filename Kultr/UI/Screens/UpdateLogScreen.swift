import SwiftUI

/** One version in the update log. */
struct UpdateLogEntry: Decodable, Identifiable {
    struct Section: Decodable, Hashable {
        let title: String
        let lines: [Line]
    }

    struct Line: Decodable, Hashable {
        /** "heading", "bullet", "subbullet" or "text". */
        let kind: String
        let text: String
    }

    let version: String
    let date: String
    let sections: [Section]
    var testBuild = false

    var id: String { version }

    private enum CodingKeys: String, CodingKey { case version, date, sections }

    init(version: String, date: String, sections: [Section], testBuild: Bool) {
        self.version = version
        self.date = date
        self.sections = sections
        self.testBuild = testBuild
    }

    /**
     * Every version, newest first: the released ones from their notes, and
     * newer test builds from their What's new pages.
     */
    static let all: [UpdateLogEntry] = {
        let released = (try? JSONDecoder().decode([UpdateLogEntry].self, from: Data(UPDATE_LOG_JSON.utf8))) ?? []
        let known = Set(released.map(\.version))
        let newest = released.first?.version ?? "0"
        let tests = WhatsNew.notes.compactMap { pair -> UpdateLogEntry? in
            let (version, items) = pair
            // A test build newer than every release; the released versions have their notes.
            guard !known.contains(version), Versions.isNewer(version, than: newest) else { return nil }
            let lines = items.map { Line(kind: "bullet", text: "**\($0.title).** \($0.text)") }
            return UpdateLogEntry(version: version, date: "", sections: [Section(title: "", lines: lines)], testBuild: true)
        }
        return (released + tests).sorted { Versions.isNewer($0.version, than: $1.version) }
    }()
}

/** Settings → About → Update log: every version's changes, in a card you scroll. */
struct UpdateLogSheet: View {
    @Environment(\.kultr) private var theme
    let onDone: () -> Void

    private static let dateIn: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateOut: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()

    var body: some View {
        let c = theme.colors
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(UpdateLogEntry.all) { entry in
                        VersionCard(entry: entry, date: Self.dateIn.date(from: entry.date).map { Self.dateOut.string(from: $0) })
                    }
                }
                .padding(16)
            }
            .background(c.background)
            .navigationTitle("Update log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
            }
        }
        .tint(c.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct VersionCard: View {
    @Environment(\.kultr) private var theme
    let entry: UpdateLogEntry
    let date: String?

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Version \(entry.version)")
                    .font(.title3.bold())
                    .foregroundStyle(c.ink)
                if entry.version == appVersion {
                    Text("This one")
                        .font(KFont.labelSmall.weight(.semibold))
                        .foregroundStyle(c.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(c.accent))
                }
                Spacer(minLength: 8)
                Text(entry.testBuild ? "KultrPre" : (date ?? ""))
                    .font(KFont.bodySmall)
                    .foregroundStyle(c.ink3)
            }
            UpdateLogLines(entry: entry)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).fill(c.sand.opacity(0.7)))
    }
}

/** One version's notes: its sections, each with its entries. */
struct UpdateLogLines: View {
    @Environment(\.kultr) private var theme
    let entry: UpdateLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(entry.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 6) {
                    if !section.title.isEmpty {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.colors.accent)
                            .padding(.top, 2)
                    }
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        LogLine(line: line)
                    }
                }
            }
        }
    }
}

private struct LogLine: View {
    @Environment(\.kultr) private var theme
    let line: UpdateLogEntry.Line

    var body: some View {
        let c = theme.colors
        let text = (try? AttributedString(markdown: line.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(line.text)
        switch line.kind {
        case "heading":
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(c.ink)
                .padding(.top, 4)
        case "bullet", "subbullet":
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(c.accent)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(c.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, line.kind == "subbullet" ? 18 : 0)
        default:
            Text(text)
                .font(.subheadline)
                .foregroundStyle(c.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
