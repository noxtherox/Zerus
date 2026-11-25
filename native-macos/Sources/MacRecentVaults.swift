import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Recent-vault presentation: per-vault icons live in this Mac's defaults and
/// Application Support, never inside the vault, so other devices are unaffected.
/// Values: nil (first letter), `letter:AB`, `emoji:😀`, `tabler:name`, `image:file.png`.
enum MacRecentVaults {
    static let recentsKey = "zerus.mac.recentVaults"
    static let iconsKey = "zerus.mac.vaultIcons"
    static var imageDirectory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/VaultIcons", isDirectory: true) }
    @MainActor private static let images = NSCache<NSString, NSImage>()

    /// Scratch folders (test fixtures, previews) never belong in the recent list.
    static func isTemporary(_ path: String) -> Bool {
        let temporary = FileManager.default.temporaryDirectory
        let roots = [temporary.standardizedFileURL.path, temporary.resolvingSymlinksInPath().standardizedFileURL.path, "/tmp", "/private/tmp"]
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.path
        return roots.contains { root in candidate == root || candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/") }
    }
    static func stored() -> [String] {
        (UserDefaults.standard.stringArray(forKey: recentsKey) ?? []).filter { !isTemporary($0) }
    }
    static func name(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }
    /// The parent folder, abbreviated, so same-named vaults stay distinguishable.
    static func location(_ path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent, home = NSHomeDirectory()
        if parent == home { return "~" }
        if parent.hasPrefix(home + "/") { return "~" + parent.dropFirst(home.count) }
        return parent
    }
    static func letter(_ path: String) -> String {
        name(path).first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "V"
    }
    static func tint(_ path: String) -> Color {
        let palette: [Color] = [.pink, .indigo, .teal, .orange, .green, .purple, .blue, .red, .mint, .brown]
        let seed = path.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return palette[Int(seed % UInt64(palette.count))]
    }
    @MainActor static func image(_ value: String) -> NSImage? {
        guard value.hasPrefix("image:") else { return nil }
        let file = String(value.dropFirst(6))
        if let cached = images.object(forKey: file as NSString) { return cached }
        guard let image = NSImage(contentsOf: imageDirectory.appendingPathComponent(file)) else { return nil }
        images.setObject(image, forKey: file as NSString); return image
    }
    /// Downscale to a square aspect-fill PNG so large photos stay cheap to draw.
    static func squarePNG(from source: URL, side: Int = 160) throws -> Data {
        guard let image = NSImage(contentsOf: source), image.size.width > 0, image.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw VaultFailure(message: "That file could not be read as an image.") }
        let target = CGFloat(side), scale = max(target / image.size.width, target / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: CGRect(x: (target - size.width) / 2, y: (target - size.height) / 2, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw VaultFailure(message: "The image could not be converted.") }
        return data
    }
}

extension MacWorkspace {
    func setVaultIcon(_ path: String, _ value: String?) {
        if let old = vaultIcons[path], old.hasPrefix("image:"), old != value {
            try? FileManager.default.removeItem(at: MacRecentVaults.imageDirectory.appendingPathComponent(String(old.dropFirst(6))))
        }
        vaultIcons[path] = value
        UserDefaults.standard.set(vaultIcons, forKey: MacRecentVaults.iconsKey)
    }
    func setVaultImage(_ path: String, from source: URL) throws {
        let data = try MacRecentVaults.squarePNG(from: source)
        try FileManager.default.createDirectory(at: MacRecentVaults.imageDirectory, withIntermediateDirectories: true)
        let file = NativeHistory.hash(path) + "-" + UUID().uuidString.prefix(8) + ".png"
        try data.write(to: MacRecentVaults.imageDirectory.appendingPathComponent(file), options: .atomic)
        setVaultIcon(path, "image:" + file)
    }
    /// Hides a vault from the recent list. The folder and its notes are untouched.
    func forgetRecentVault(_ path: String) {
        recentVaults.removeAll { $0 == path }
        UserDefaults.standard.set(recentVaults, forKey: MacRecentVaults.recentsKey)
        setVaultIcon(path, nil)
        if root?.path != path { UserDefaults.standard.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(path)) }
    }
    func createVault() {
        guard !busy, !preparingToClose else { return }
        let panel = NSSavePanel(); panel.title = "New Vault"; panel.prompt = "Create Vault"; panel.nameFieldLabel = "Vault name:"
        panel.nameFieldStringValue = "Notes"; panel.canCreateDirectories = true; panel.message = "Zerus creates a new folder for your Markdown notes."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        catch { issue = "The vault folder could not be created. " + error.localizedDescription; return }
        Task { await openVault(url) }
    }
}

struct MacVaultIconView: View {
    let path: String
    let value: String?
    var size: CGFloat = 30
    var body: some View {
        let tint = MacRecentVaults.tint(path)
        ZStack {
            if let value, value.hasPrefix("image:"), let image = MacRecentVaults.image(value) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let value, value.hasPrefix("emoji:") {
                Color.primary.opacity(0.08)
                Text(String(value.dropFirst(6))).font(.system(size: size * 0.6))
            } else if let value, value.hasPrefix("tabler:") {
                tint
                MacFolderIcon(value: value, size: size * 0.58).foregroundStyle(.white)
            } else {
                tint
                Text(value.flatMap { $0.hasPrefix("letter:") ? String($0.dropFirst(7)) : nil } ?? MacRecentVaults.letter(path))
                    .font(.system(size: size * (((value?.count ?? 0) > 8) ? 0.36 : 0.46), weight: .bold, design: .rounded))
                    .foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1).padding(.horizontal, 2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct MacRecentVaultRow: View {
    let path: String
    let icon: String?
    let current: Bool
    let open: () -> Void
    let changeIcon: () -> Void
    let remove: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 12) {
                    MacVaultIconView(path: path, value: icon, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(MacRecentVaults.name(path)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(MacRecentVaults.location(path)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open " + MacRecentVaults.name(path))
            HStack(spacing: 2) {
                Menu { actions } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More")
                Button(action: remove) { Image(systemName: "xmark.circle.fill").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help("Remove from Recents").accessibilityLabel("Remove " + MacRecentVaults.name(path) + " from Recents")
            }.foregroundStyle(.secondary).opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .onHover { hovering = $0 }
        .contextMenu { Button("Open") { open() }; actions }
    }
    @ViewBuilder private var actions: some View {
        Button("Change Icon…") { changeIcon() }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        Divider()
        Button("Remove from Recents", role: .destructive) { remove() }.disabled(current)
    }
}

struct MacVaultIconRequest: Identifiable {
    let path: String
    var id: String { path }
}

struct MacVaultIconPicker: View {
    @Bindable var workspace: MacWorkspace
    let request: MacVaultIconRequest
    private enum Kind: String, CaseIterable, Identifiable { case letter = "Letter", emoji = "Emoji", icon = "Icon", image = "Image"; var id: String { rawValue } }
    @ObservedObject private var catalog = MacFolderIconCatalog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .letter
    @State private var letters = ""
    @State private var emoji = ""
    @State private var query = ""
    @State private var count = 160
    @State private var issue: String?
    private var path: String { request.path }
    private var value: String? { workspace.vaultIcons[path] }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                MacVaultIconView(path: path, value: value, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Icon for “" + MacRecentVaults.name(path) + "”").font(.title2.bold())
                    Text(MacRecentVaults.location(path)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Picker("Style", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            Group {
                switch kind {
                case .letter:
                    HStack {
                        TextField(MacRecentVaults.letter(path), text: $letters).textFieldStyle(.roundedBorder).frame(width: 90)
                            .onChange(of: letters) { _, new in if new.count > 2 { letters = String(new.prefix(2)) } }
                            .onSubmit(useLetters)
                        Button("Use Letters", action: useLetters).disabled(letters.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Up to two characters on a colored tile. Leave empty to use the vault's first letter.").font(.caption).foregroundStyle(.secondary)
                case .emoji:
                    HStack {
                        TextField("One emoji", text: $emoji).textFieldStyle(.roundedBorder).frame(width: 90).onSubmit(useEmoji)
                        Button("Emoji & Symbols") { NSApp.orderFrontCharacterPalette(nil) }
                        Button("Use Emoji", action: useEmoji).disabled(!validEmoji)
                    }
                case .icon:
                    TextField("Search icons…", text: $query).textFieldStyle(.roundedBorder).onChange(of: query) { _, _ in count = 160 }
                    let matches = catalog.matches(query)
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                            ForEach(matches.prefix(count)) { entry in
                                let candidate = "tabler:" + entry.name
                                Button { workspace.setVaultIcon(path, candidate) } label: {
                                    MacFolderIcon(value: candidate).frame(width: 38, height: 38)
                                        .background(value == candidate ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
                                }.buttonStyle(MacBoxButtonStyle()).help(entry.label).accessibilityLabel("Use " + entry.label + " icon")
                            }
                        }
                        if matches.count > count { Button("Show more (\(matches.count - count) remaining)") { count += 160 }.padding(.top, 8) }
                        if matches.isEmpty { Text(catalog.entries.isEmpty ? (catalog.issue ?? "Loading icons…") : "No matching icons").foregroundStyle(.secondary).padding() }
                    }.frame(height: 240)
                case .image:
                    HStack {
                        Button("Choose Image…", action: chooseImage)
                        Text("PNG, JPEG, HEIC… cropped to a square.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Reset to Letter") { letters = ""; workspace.setVaultIcon(path, nil) }.disabled(value == nil)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 520)
        .onAppear {
            if let value {
                if value.hasPrefix("letter:") { kind = .letter; letters = String(value.dropFirst(7)) }
                else if value.hasPrefix("emoji:") { kind = .emoji; emoji = String(value.dropFirst(6)) }
                else if value.hasPrefix("tabler:") { kind = .icon }
                else if value.hasPrefix("image:") { kind = .image }
            }
        }
        .task { await catalog.load() }
    }
    private var validEmoji: Bool { emoji.count == 1 && emoji.unicodeScalars.contains { !$0.isASCII } }
    private func useLetters() {
        let text = letters.trimmingCharacters(in: .whitespaces)
        workspace.setVaultIcon(path, text.isEmpty ? nil : "letter:" + text.uppercased())
    }
    private func useEmoji() { if validEmoji { workspace.setVaultIcon(path, "emoji:" + emoji) } }
    private func chooseImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false; panel.prompt = "Use Image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try workspace.setVaultImage(path, from: url); issue = nil } catch { issue = error.localizedDescription }
    }
}
