import AppKit
import SwiftUI

/// Read-only catalogue snapshot: previewing never opens, saves or fetches a resource.
struct MacNotePreviewSnapshot {
    let note: NoteDocument
    let heading: String?
    init?(value: String, notes: [NoteDocument], currentPath: String) {
        let url = URL(string: value)
        let reference = url.flatMap(NoteReference.init(url:)) ?? NoteReference(target: value, label: value, explicitLabel: false)
        let candidates: [NoteDocument]
        if let url, MacHeadings.localFragment(url) != nil { candidates = notes.filter { $0.path == currentPath && !$0.trashed } }
        else if let url, url.scheme == nil, !value.hasPrefix("#"), !url.relativePath.isEmpty,
                let relative = [String(URL(fileURLWithPath: "/" + currentPath).deletingLastPathComponent().appendingPathComponent(url.relativePath).standardizedFileURL.path.dropFirst()), url.relativePath]
                    .compactMap({ path in notes.first { !$0.trashed && $0.path == path } }).first {
            candidates = [relative]
        } else { candidates = reference.targets(in: notes, includeHeadingFragments: true) }
        guard candidates.count == 1, let note = candidates.first else { return nil }
        self.note = note
        heading = url.flatMap(MacHeadings.localFragment) ?? reference.heading(in: note) ?? (url?.scheme == nil && !value.hasPrefix("#") ? url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.fragment } : nil)
    }
    var excerpt: String {
        let body = note.parts.body as NSString
        var start = heading.flatMap { MacHeadings.target($0, in: note.parts.body)?.range.location } ?? 0
        if heading == nil, let first = MacHeadings.entries(note.parts.body).first, first.range.location == 0, first.level == 1, first.title == note.title {
            start = NSMaxRange(first.range)
        }
        return String(body.substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines).prefix(3000))
    }
}

@MainActor final class MacNotePreview {
    private var host: NSView?
    private var dismissal: Task<Void, Never>?
    private var pending: Task<Void, Never>?
    private var value: String?
    private var source: String?
    private weak var anchor: NSTextView?
    var shown: Bool { host?.superview != nil }
    func hide() {
        pending?.cancel(); pending = nil; dismissal?.cancel(); dismissal = nil
        if let host, let anchor, let responder = anchor.window?.firstResponder as? NSView, responder.isDescendant(of: host) {
            anchor.window?.makeFirstResponder(anchor)
        }
        value = nil; source = nil; host?.removeFromSuperview(); host = nil; anchor = nil
    }
    func leave() {
        pending?.cancel(); pending = nil; dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, let self else { return }
            if let host = self.host, let window = host.window,
               window.convertToScreen(host.convert(host.bounds, to: nil)).contains(NSEvent.mouseLocation) { return }
            self.hide()
        }
    }
    func show(value: String, at range: NSRange, view: NSTextView, notes: [NoteDocument], path: String, immediate: Bool = false, open: @escaping () -> Void) {
        guard let snapshot = MacNotePreviewSnapshot(value: value, notes: notes, currentPath: path) else { hide(); return }
        dismissal?.cancel(); dismissal = nil
        if self.value == value, source == snapshot.note.content, (pending != nil || shown) { return }
        hide(); self.value = value; source = snapshot.note.content; anchor = view
        pending = Task { [weak self, weak view] in
            if !immediate { try? await Task.sleep(nanoseconds: 450_000_000) }
            guard !Task.isCancelled, let self, let view, view.window != nil,
                  NSMaxRange(range) <= view.attributedString().length else { return }
            let rich = view.attributedString()
            guard range.length > 0, String(describing: rich.attribute(.link, at: range.location, effectiveRange: nil) ?? "") == value,
                  let manager = view.layoutManager, let container = view.textContainer else { self.hide(); return }
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y).intersection(view.visibleRect)
            guard !rect.isEmpty else { self.hide(); return }
            guard let scroll = view.enclosingScrollView else { self.hide(); return }
            let host = NSHostingView(rootView: MacNotePreviewView(snapshot: snapshot, open: { [weak self] in self?.hide(); open() }, close: { [weak self] in self?.hide() }))
            let width = min(CGFloat(360), scroll.bounds.width - 16), height = min(CGFloat(290), scroll.bounds.height - 16)
            guard width > 0, height > 0 else { self.hide(); return }
            let link = scroll.convert(rect, from: view), y = scroll.isFlipped ? link.maxY + 5 : link.minY - height - 5
            host.frame = NSRect(x: max(8, min(link.minX, scroll.bounds.width - width - 8)), y: max(8, min(y, scroll.bounds.height - height - 8)), width: width, height: height)
            self.host = host; scroll.addSubview(host)
            self.pending = nil
        }
    }
}

private struct MacNotePreviewView: View {
    let snapshot: MacNotePreviewSnapshot
    let open: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(snapshot.note.title).font(.headline).lineLimit(2)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(MacBoxButtonStyle()).help("Close preview").accessibilityLabel("Close preview").keyboardShortcut(.cancelAction)
            }
            Text(snapshot.note.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let heading = snapshot.heading, MacHeadings.target(heading, in: snapshot.note.parts.body) == nil {
                Label("Heading no longer exists", systemImage: "exclamationmark.triangle").font(.caption)
            }
            Divider()
            ScrollView {
                Text(AttributedString(MacMarkdown.render(snapshot.excerpt)))
                    .font(.callout).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    .environment(\.openURL, OpenURLAction { _ in .handled })
            }
            HStack { Text("Note preview").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Open note", action: open) }
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).overlay { RoundedRectangle(cornerRadius: 10).stroke(.quaternary) }
    }
}
