import SwiftUI
import AppKit

/// Shared metrics so every inspector section lines up on one grid.
enum MacInspectorMetrics {
    static let keyWidth: CGFloat = 96
    static let rowHeight: CGFloat = 26
    static let iconWidth: CGFloat = 16
    static let rowRadius: CGFloat = 6
}

extension NativePropertyType {
    var inspectorIcon: String {
        switch self {
        case .text: "text.alignleft"
        case .url: "link"
        case .number: "number"
        case .date: "calendar"
        case .checkbox: "checkmark.square"
        case .list: "list.bullet"
        case .relation: "arrow.triangle.branch"
        case .unsupported: "questionmark.square.dashed"
        }
    }
}

/// One property: type glyph, name and a type-aware value. The whole row edits
/// on click; checkboxes toggle in place and URLs keep a separate open control.
struct MacInspectorPropertyRow: View {
    @Environment(\.macTheme) private var theme
    let name: String
    let type: NativePropertyType
    let value: NativePropertyValue?
    let display: String
    let preserved: Bool
    let disabled: Bool
    let edit: () -> Void
    let toggle: (Bool) -> Void
    @State private var hovering = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: type.inspectorIcon).font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: MacInspectorMetrics.iconWidth)
                Text(name).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }.frame(width: MacInspectorMetrics.keyWidth, alignment: .leading).help(name)
            valueView.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 6).frame(minHeight: MacInspectorMetrics.rowHeight)
        .background(hovering && !disabled ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: MacInspectorMetrics.rowRadius))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if !disabled && !preserved && type != .checkbox { edit() } }
        .contextMenu { Button("Edit property…", action: edit).disabled(disabled || preserved) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue(preserved ? "Preserved YAML" : isEmpty ? "Empty" : display)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !disabled && !preserved { type == .checkbox ? toggle(!checked) : edit() } }
    }
    private var isEmpty: Bool { value == nil || display.isEmpty }
    private var checked: Bool { if case .checkbox(let on) = value { return on }; return display == "true" }
    @ViewBuilder private var valueView: some View {
        if preserved {
            Text("Preserved YAML").italic().foregroundStyle(.tertiary).help("This value uses YAML the inspector does not edit. It is kept unchanged.")
        } else if type == .checkbox {
            Toggle("", isOn: Binding(get: { checked }, set: toggle)).toggleStyle(.checkbox).labelsHidden().disabled(disabled)
        } else if isEmpty {
            Text("Empty").foregroundStyle(.quaternary)
        } else if type == .list {
            MacInspectorFlow(spacing: 4) {
                ForEach(Array((value?.selections ?? [display]).enumerated()), id: \.offset) { _, item in MacInspectorChip(text: item) }
            }
        } else if type == .url {
            HStack(spacing: 4) {
                Text(Self.shortURL(display)).foregroundStyle(theme.color(.link)).lineLimit(1).truncationMode(.middle).help(display)
                if let url = URL(string: display), url.scheme != nil {
                    Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right.square").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(hovering ? theme.color(.link) : Color.secondary.opacity(0.5))
                        .help("Open " + display).accessibilityLabel("Open link")
                }
            }
        } else if type == .number {
            Text(display).monospacedDigit().lineLimit(1)
        } else {
            Text(display).lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }
    }
    static func shortURL(_ text: String) -> String {
        guard let url = URL(string: text), let host = url.host else { return text }
        let path = url.path == "/" ? "" : url.path
        return host.replacingOccurrences(of: "www.", with: "") + path
    }
}

struct MacInspectorChip: View {
    @Environment(\.macTheme) private var theme
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(theme.color(.accent).opacity(0.14), in: Capsule())
            .foregroundStyle(theme.color(.text))
    }
}

/// Leading-aligned wrapping layout for chips.
struct MacInspectorFlow: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .init(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.init(width: width, height: nil)), itemWidth = min(size.width, width)
            let next = current.items.isEmpty ? itemWidth : current.width + spacing + itemWidth
            if !current.items.isEmpty && next > width { rows.append(current); current = ([index], itemWidth, size.height) }
            else { current.items.append(index); current.width = next; current.height = max(current.height, size.height) }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// Quiet text-with-icon action used at the end of a section ("Add property").
struct MacInspectorAction: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium)).frame(width: MacInspectorMetrics.iconWidth)
                Text(title)
                Spacer(minLength: 0)
            }.font(.system(size: 12.5)).padding(.horizontal, 6).frame(minHeight: MacInspectorMetrics.rowHeight)
                .foregroundStyle(hovering ? .primary : .secondary)
                .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: MacInspectorMetrics.rowRadius))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
    }
}

/// A linked note in Relations: title, optional folder, hover-revealed remove.
struct MacInspectorNoteLink: View {
    @Environment(\.macTheme) private var theme
    let title: String
    var detail: String?
    var available = true
    let open: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: open) {
            HStack(spacing: 7) {
                Image(systemName: available ? "doc.text" : "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(available ? AnyShapeStyle(theme.color(.link)) : AnyShapeStyle(.orange))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(available ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)).lineLimit(2)
                    if let detail, !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle) }
                }
                Spacer(minLength: 0)
                if hovering && available { Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color.primary.opacity(hovering ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.07)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!available).onHover { hovering = $0 }
    }
}

/// Group heading inside Relations: name, count and an edit/add control.
struct MacInspectorGroupHeader: View {
    let title: String
    let count: Int
    var icon = "arrow.triangle.branch"
    var edit: (() -> Void)?
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10.5))
            Text(title).fontWeight(.semibold)
            if count > 0 { Text(String(count)).monospacedDigit().foregroundStyle(.tertiary) }
            Spacer(minLength: 0)
            if let edit {
                Button(action: edit) { Image(systemName: "plus").font(.system(size: 11, weight: .medium)).frame(width: 18, height: 18).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Edit " + title).accessibilityLabel("Edit " + title)
            }
        }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 2).padding(.top, 4)
    }
}

/// Revisions summary card: current version with its timestamp and the two
/// recovery entry points.
struct MacInspectorRevisionCard: View {
    let current: NativeNoteRevision?
    let count: Int
    let browse: () -> Void
    let history: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: browse) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 13)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(current.map { "Revision \($0.number)" } ?? "No revisions yet").font(.system(size: 12.5, weight: .medium))
                            if current != nil { Text("Current").font(.system(size: 10.5, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 1).background(Color.green.opacity(0.18), in: Capsule()).foregroundStyle(.green) }
                        }
                        if let date = current?.date { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(.tertiary) }
                    }
                    Spacer(minLength: 0)
                    if count > 1 { Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.tertiary) }
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.07)))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).help("Browse revisions")
            MacInspectorAction(title: "Automatic history", icon: "clock", action: history)
        }
    }
}

/// Attachment row: file glyph by extension and its name.
struct MacInspectorFileRow: View {
    let name: String
    let open: () -> Void
    @State private var hovering = false
    private var icon: String {
        switch (name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg": "photo"
        case "pdf": "doc.richtext"
        case "mov", "mp4", "m4v": "film"
        case "mp3", "m4a", "wav": "waveform"
        case "zip": "doc.zipper"
        default: "doc"
        }
    }
    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: MacInspectorMetrics.iconWidth)
                Text(name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }.font(.system(size: 12.5)).padding(.horizontal, 6).frame(minHeight: MacInspectorMetrics.rowHeight)
                .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: MacInspectorMetrics.rowRadius))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }.help(name)
    }
}

/// Note location footer: folder breadcrumb, selectable.
struct MacInspectorPathFooter: View {
    let path: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "folder").font(.system(size: 10.5))
            Text(path).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
        }.font(.system(size: 11)).foregroundStyle(.tertiary).padding(.horizontal, 6).help(path)
    }
}
