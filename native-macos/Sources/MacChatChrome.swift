import SwiftUI
import AppKit

/// AI chat surfaces derived from the user's seven theme roles: the list uses
/// the sidebar colours, the conversation uses the editor colours.
struct MacChatPalette {
    let editor, sidebar, sidebarText, sidebarMuted, surface, text, muted, line, hover, accent, accentSoft: Color
    init(_ theme: MacTheme) {
        editor = theme.color(.editorBg); sidebar = theme.color(.sidebarBg); sidebarText = theme.color(.sidebarFg)
        surface = theme.color(.surface); text = theme.color(.text); accent = theme.color(.accent)
        sidebarMuted = sidebarText.opacity(0.55); muted = text.opacity(0.6); line = text.opacity(0.1)
        hover = text.opacity(0.06); accentSoft = accent.opacity(0.16)
    }
}

/// Borderless icon control used for secondary chat actions.
struct MacChatIconButton: View {
    let systemImage: String
    let help: String
    let palette: MacChatPalette
    var size: CGFloat = 26
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).macFont(.system(size: size * 0.48, weight: .medium))
                .frame(width: size, height: size).foregroundStyle(palette.muted)
                .background(hovering && enabled ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(help).accessibilityLabel(help).opacity(enabled ? 1 : 0.4).onHover { hovering = $0 }
    }
}

/// Capsule used for context notes, documents and the model indicator.
struct MacChatChip: View {
    let title: String
    let systemImage: String
    let palette: MacChatPalette
    var emphasized = false
    var action: (() -> Void)? = nil
    var remove: (() -> Void)? = nil
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        HStack(spacing: 5) {
            label
            if let remove {
                Button(action: remove) { Image(systemName: "xmark").macFont(.system(size: 8, weight: .bold)).foregroundStyle(palette.muted).frame(width: 14, height: 14).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Remove " + title).help("Remove " + title)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(palette.hover, in: Capsule()).overlay(Capsule().stroke(palette.line))
        .opacity(enabled ? 1 : 0.5)
    }
    @ViewBuilder private var label: some View {
        let content = HStack(spacing: 4) {
            Image(systemName: systemImage).macFont(.system(size: 10)).foregroundStyle(emphasized ? palette.accent : palette.muted)
            Text(title).macFont(.caption).lineLimit(1).foregroundStyle(palette.text)
        }
        if let action { Button(action: action) { content.contentShape(Rectangle()) }.buttonStyle(.plain) } else { content }
    }
}

/// One conversation in the themed list. Device is shown only when another
/// device owns the conversation.
struct MacChatConversationRow: View {
    let item: MacConversationListEntry
    let selected: Bool
    let ownedHere: Bool
    let palette: MacChatPalette
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 6) {
            Text(item.title).lineLimit(1).truncationMode(.tail).macFont(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? palette.text : palette.sidebarText)
            Spacer(minLength: 4)
            if !ownedHere {
                Image(systemName: item.owner.name.localizedCaseInsensitiveContains("iphone") ? "iphone" : item.owner.name.localizedCaseInsensitiveContains("ipad") ? "ipad" : "desktopcomputer")
                    .macFont(.system(size: 10)).foregroundStyle(palette.sidebarMuted).help("Owned by " + item.owner.name)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? palette.accentSoft : hovering ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle()).onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title + (ownedHere ? "" : ", owned by " + item.owner.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum MacChatListGroup: Int, CaseIterable {
    case today, yesterday, week, month, older
    var title: String { switch self { case .today: "Today"; case .yesterday: "Yesterday"; case .week: "Previous 7 days"; case .month: "Previous 30 days"; case .older: "Older" } }
    private static let fractional: ISO8601DateFormatter = { let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value }()
    private static let plain = ISO8601DateFormatter()
    static func date(_ value: String) -> Date? { fractional.date(from: value) ?? plain.date(from: value) }
    static func group(_ value: String, now: Date = Date(), calendar: Calendar = .current) -> Self {
        guard let date = date(value) else { return .older }
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        let start = calendar.startOfDay(for: now)
        if let week = calendar.date(byAdding: .day, value: -7, to: start), date >= week { return .week }
        if let month = calendar.date(byAdding: .day, value: -30, to: start), date >= month { return .month }
        return .older
    }
    /// Keeps the controller's order (newest first) inside each group.
    static func sections(_ items: [MacConversationListEntry], now: Date = Date()) -> [MacChatListSection] {
        let grouped = Dictionary(grouping: items) { group($0.updatedAt, now: now) }
        return allCases.compactMap { group in grouped[group].map { MacChatListSection(group: group, items: $0) } }
    }
}
struct MacChatListSection: Identifiable {
    let group: MacChatListGroup
    let items: [MacConversationListEntry]
    var id: Int { group.rawValue }
}

/// Starter prompts offered on an empty conversation. They only fill the
/// draft; nothing is sent until the user presses Send.
struct MacChatStarter: Identifiable {
    let title: String, detail: String, prompt: String
    var id: String { title }
    static let all: [Self] = [
        .init(title: "Summarize", detail: "Key points of the shared notes", prompt: "Summarize the key points of the shared notes."),
        .init(title: "Fix formatting", detail: "Headings, lists and spacing", prompt: "Clean up the formatting of the shared note: headings, lists, spacing and emphasis. Keep the content unchanged."),
        .init(title: "Find related", detail: "Linked and similar notes", prompt: "Find notes related to the shared notes and explain how they connect."),
        .init(title: "Draft a user story", detail: "With acceptance criteria", prompt: "Turn the shared note into a concise user story with acceptance criteria."),
    ]
}

struct MacChatEmptyState: View {
    let contextTitles: [String]
    let palette: MacChatPalette
    let choose: (MacChatStarter) -> Void
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles").macFont(.system(size: 26)).foregroundStyle(palette.accent)
            Text("Think it through.").macFont(.title3.bold()).foregroundStyle(palette.text)
            if contextTitles.isEmpty { Text("Ask a question, or add notes to share as context.").foregroundStyle(palette.muted) }
            else {
                HStack(spacing: 6) {
                    Text("Working with").foregroundStyle(palette.muted)
                    MacChatChip(title: contextTitles.count == 1 ? contextTitles[0] : "\(contextTitles.count) notes", systemImage: "doc.text", palette: palette, emphasized: true)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    ForEach(MacChatStarter.all) { starter in MacChatStarterCard(starter: starter, palette: palette) { choose(starter) } }
                }.frame(maxWidth: 440).padding(.top, 10)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}
private struct MacChatStarterCard: View {
    let starter: MacChatStarter
    let palette: MacChatPalette
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(starter.title).macFont(.callout.weight(.semibold)).foregroundStyle(palette.text)
                Text(starter.detail).macFont(.caption).foregroundStyle(palette.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? palette.hover : palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.line))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }.accessibilityHint("Fills the message field")
    }
}

/// Shown instead of the composer when this Mac cannot write to the conversation.
struct MacChatBanner<Action: View>: View {
    let systemImage: String
    let message: String
    let palette: MacChatPalette
    @ViewBuilder let action: () -> Action
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(palette.muted)
            Text(message).macFont(.callout).foregroundStyle(palette.muted).frame(maxWidth: .infinity, alignment: .leading)
            action()
        }
        .padding(12).background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// Pending agent proposals for the open conversation. The full before/after
/// review and approval stay in Agent runs, which this card opens.
struct MacChatPendingProposals: View {
    @ObservedObject var controller: MacAgentController
    @ObservedObject var chat: MacChatController
    let palette: MacChatPalette
    let locked: Bool
    let review: (NativeAgentRecord, Set<UUID>) -> Void
    let reject: (NativeAgentRecord, UUID) -> Void
    var body: some View {
        if let record = controller.current, record.run.chatID == chat.selectedID, !record.run.pending.isEmpty {
            let disabled = locked || controller.running || !chat.writable
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.ellipsis").foregroundStyle(palette.accent)
                    Text(record.run.pending.count == 1 ? "Proposed change" : "\(record.run.pending.count) proposed changes").macFont(.callout.weight(.semibold)).foregroundStyle(palette.text)
                    Text("NOT SAVED").macFont(.system(size: 9.5, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(Color.orange).background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                    Spacer()
                }.padding(.horizontal, 12).padding(.vertical, 9)
                Divider().overlay(palette.line)
                ForEach(record.run.pending) { proposal in
                    HStack {
                        Image(systemName: "doc.text").macFont(.caption).foregroundStyle(palette.muted)
                        Text(proposal.label).macFont(.callout).foregroundStyle(palette.text).lineLimit(2)
                        Spacer()
                        Button("Discard") { reject(record, proposal.id) }.buttonStyle(.borderless).foregroundStyle(palette.muted).macFont(.caption).disabled(disabled)
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                }
                Divider().overlay(palette.line)
                HStack {
                    Text("Review shows the exact before and after for each file.").macFont(.caption).foregroundStyle(palette.muted)
                    Spacer()
                    Button("Review…") { review(record, Set(record.run.pending.map(\.id))) }.buttonStyle(.borderedProminent).controlSize(.small).disabled(disabled)
                }.padding(.horizontal, 12).padding(.vertical, 8)
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.line))
        }
    }
}

enum MacChatLinks {
    static let scheme = "zerus-chat-note"
    /// Turns `[[target|Label]]` and `[[target]]` into Markdown links the chat
    /// can open, so stable note links read as their titles instead of IDs.
    static func linked(_ text: String) -> String {
        guard text.contains("[[") else { return text }
        let pattern = try! NSRegularExpression(pattern: #"\[\[([^\[\]|\n]+?)(?:\|([^\[\]\n]+?))?\]\]"#)
        let source = text as NSString
        var result = "", cursor = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let target = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let label = match.range(at: 2).location == NSNotFound ? (target.hasPrefix("zerus:") ? "note" : target) : source.substring(with: match.range(at: 2))
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~:"))) ?? target
            let escaped = label.replacingOccurrences(of: "]", with: "\\]").replacingOccurrences(of: "[", with: "\\[")
            result += "[\(escaped)](\(scheme):\(encoded))"
            cursor = match.range.location + match.range.length
        }
        return result + source.substring(from: cursor)
    }
    static func target(_ url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        let raw = url.absoluteString.dropFirst(scheme.count + 1)
        return String(raw).removingPercentEncoding
    }
}
