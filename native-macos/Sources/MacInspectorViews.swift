import SwiftUI
import AppKit

/// Shared metrics so every inspector section lines up on one grid.
enum MacInspectorMetrics {
    static let keyWidth: CGFloat = 116
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
/// on click; checkboxes toggle in place and URLs open on click, with a trailing
/// pencil to edit.
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
    @State private var linkHovering = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: type.inspectorIcon).macFont(.system(size: 11)).foregroundStyle(.tertiary).frame(width: MacInspectorMetrics.iconWidth)
                Text(name).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }.frame(width: MacInspectorMetrics.keyWidth, alignment: .leading).help(name)
            valueView.frame(maxWidth: .infinity, alignment: .leading)
        }
        .macFont(.system(size: 12.5))
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
                if let url = URL(string: display), url.scheme != nil {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Text(Self.shortURL(display)).foregroundStyle(theme.color(.link)).lineLimit(1).truncationMode(.middle)
                            .underline(linkHovering)
                    }
                    .buttonStyle(.plain).onHover { linkHovering = $0 }
                    .help("Open " + display).accessibilityLabel("Open link")
                } else {
                    Text(Self.shortURL(display)).foregroundStyle(theme.color(.link)).lineLimit(1).truncationMode(.middle).help(display)
                }
                Spacer(minLength: 4)
                if !disabled {
                    Button(action: edit) { Image(systemName: "pencil").macFont(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(hovering ? Color.secondary : Color.secondary.opacity(0.4))
                        .help("Edit " + name).accessibilityLabel("Edit link")
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
        Text(text).macFont(.system(size: 11.5, weight: .medium)).lineLimit(1)
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
                Image(systemName: icon).macFont(.system(size: 11, weight: .medium)).frame(width: MacInspectorMetrics.iconWidth)
                Text(title)
                Spacer(minLength: 0)
            }.macFont(.system(size: 12.5)).padding(.horizontal, 6).frame(minHeight: MacInspectorMetrics.rowHeight)
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
    /// The linked note's folder icon; notes in folders without one keep the document symbol.
    var icon: String?
    /// Shown as a trash button while hovering; nil for read-only rows such as backlinks.
    var removeHelp = "Remove relation"
    var remove: (() -> Void)?
    let open: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: open) {
            HStack(spacing: 7) {
                if available, let icon {
                    MacFolderIcon(value: icon, size: 13).macFont(.system(size: 11)).foregroundStyle(theme.color(.link))
                } else {
                    Image(systemName: available ? "doc.text" : "exclamationmark.triangle").macFont(.system(size: 11)).foregroundStyle(available ? AnyShapeStyle(theme.color(.link)) : AnyShapeStyle(.orange))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).macFont(.system(size: 12.5, weight: .medium)).foregroundStyle(available ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)).lineLimit(2)
                    if let detail, !detail.isEmpty { Text(detail).macFont(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle) }
                }
                Spacer(minLength: 0)
                // Reserve the trash button's width so titles do not reflow on hover.
                if remove != nil { Color.clear.frame(width: 20, height: 1) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color.primary.opacity(hovering ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.07)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!available)
        // Outside the (possibly disabled) open button so unavailable links can be removed too.
        .overlay(alignment: .trailing) {
            if let remove, hovering { MacInspectorRemoveButton(help: removeHelp, action: remove).padding(.trailing, 6) }
        }
        .onHover { hovering = $0 }
    }
}

private struct MacInspectorRemoveButton: View {
    let help: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "trash").macFont(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(hovering ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(hovering ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .onHover { hovering = $0 }.help(help).accessibilityLabel(help)
    }
}

/// Shown after a relation is removed; Undo relinks both notes together.
struct MacRelationUndoBanner: View {
    let text: String
    let disabled: Bool
    let undo: () -> Void
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "trash").macFont(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(text).macFont(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 4)
            Button("Undo", action: undo).buttonStyle(.plain).macFont(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
                .disabled(disabled).help("Link this note again on both sides")
            Button(action: dismiss) { Image(systemName: "xmark").macFont(.system(size: 9.5, weight: .semibold)).frame(width: 16, height: 16).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundStyle(.tertiary).help("Dismiss").accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.07)))
        .padding(.bottom, 4)
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
            Image(systemName: icon).macFont(.system(size: 10.5))
            Text(title).fontWeight(.semibold)
            if count > 0 { Text(String(count)).monospacedDigit().foregroundStyle(.tertiary) }
            Spacer(minLength: 0)
            if let edit {
                Button(action: edit) { Image(systemName: "plus").macFont(.system(size: 11, weight: .medium)).frame(width: 18, height: 18).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Edit " + title).accessibilityLabel("Edit " + title)
            }
        }.macFont(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.top, 4)
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
                    Image(systemName: "clock.arrow.circlepath").macFont(.system(size: 13)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(current.map { "Revision \($0.number)" } ?? "No revisions yet").macFont(.system(size: 12.5, weight: .medium))
                            if current != nil { Text("Current").macFont(.system(size: 10.5, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 1).background(Color.green.opacity(0.18), in: Capsule()).foregroundStyle(.green) }
                        }
                        if let date = current?.date { Text(date.formatted(date: .abbreviated, time: .shortened)).macFont(.system(size: 11)).foregroundStyle(.tertiary) }
                    }
                    Spacer(minLength: 0)
                    if count > 1 { Text("\(count)").macFont(.system(size: 11)).monospacedDigit().foregroundStyle(.tertiary) }
                    Image(systemName: "chevron.right").macFont(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
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
                Image(systemName: icon).macFont(.system(size: 11)).foregroundStyle(.secondary).frame(width: MacInspectorMetrics.iconWidth)
                Text(name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }.macFont(.system(size: 12.5)).padding(.horizontal, 6).frame(minHeight: MacInspectorMetrics.rowHeight)
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
            Image(systemName: "folder").macFont(.system(size: 10.5))
            Text(path).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
        }.macFont(.system(size: 11)).foregroundStyle(.tertiary).padding(.horizontal, 6).help(path)
    }
}
