import SwiftUI
import AppKit
import Markdown

@MainActor final class MacExternalImages: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var loading = false
    @Published private(set) var issue: String?
    private var versions: [String: NativeExternalProjectFiles.ImageVersion] = [:]
    private var projectID: UUID?
    private var generation = UUID()
    static func references(in markdown: String) -> [String] {
        var values = Set<String>()
        func walk(_ node: any Markup) {
            let reference: String?
            if let image = node as? Markdown.Image { reference = MacInlineImage(image).reference }
            else if let html = node as? InlineHTML { reference = MacInlineImage(html: html.rawHTML)?.reference }
            else if let html = node as? HTMLBlock { reference = MacInlineImage(html: html.rawHTML)?.reference }
            else { reference = nil }
            if let reference, let url = URL(string: reference), url.scheme == nil || url.isFileURL { values.insert(reference) }
            for child in node.children { walk(child) }
        }
        walk(Document(parsing: markdown)); return values.sorted()
    }
    func load(project: NativeExternalProjectFiles?, markdown: String) async {
        let token = UUID(); generation = token
        guard let project else { images = [:]; versions = [:]; projectID = nil; loading = false; issue = nil; return }
        if projectID != project.id { images = [:]; versions = [:]; projectID = project.id }
        let references = Self.references(in: markdown), wanted = Set(references)
        images = images.filter { wanted.contains($0.key) }; versions = versions.filter { wanted.contains($0.key) }
        loading = !references.isEmpty; issue = nil
        defer { if generation == token { loading = false } }
        for reference in references {
            do {
                try Task.checkCancellation()
                let version = try await project.imageVersion(reference)
                guard generation == token else { return }
                if versions[reference] == version, images[reference] != nil { continue }
                let image = try await project.thumbnail(reference)
                try Task.checkCancellation(); guard generation == token else { return }
                images[reference] = NSImage(cgImage: image, size: .zero); versions[reference] = version
            } catch is CancellationError { return }
            catch {
                guard generation == token else { return }
                images.removeValue(forKey: reference); versions.removeValue(forKey: reference)
                issue = "An image preview is unavailable: " + error.localizedDescription
            }
        }
    }
}
