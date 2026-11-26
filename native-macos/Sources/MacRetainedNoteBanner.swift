import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum MacNoteDiskChange: Equatable {
    case modified, replaced, missing, unavailable, moved(String)
    var message: String {
        switch self {
        case .modified: return "This note changed outside Zerus. Your local text is kept here."
        case .replaced: return "A different note now occupies this path. Your original text is kept here."
        case .unavailable: return "The original note cannot be read right now. Your text is kept here."
        case .missing: return "This note was moved or removed outside Zerus. Its text is kept here."
        case .moved(let path): return "This note moved to " + path + ". Your local text is kept here."
        }
    }
}

struct MacRetainedNoteBanner: View {
    @Bindable var workspace: MacWorkspace
    let change: MacNoteDiskChange
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(change.message, systemImage: "doc.badge.exclamationmark").macFont(.callout)
            HStack {
                Text(workspace.retainedExportReady ? "Your current text was exported." : "Export a copy before leaving this retained text.").macFont(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Export text…") { export() }
                if change != .unavailable { Button(change == .missing ? "Close retained note" : "Use saved version") {
                    Task { do { try await workspace.useSavedNoteAfterExport() } catch { workspace.issue = error.localizedDescription } }
                }.disabled(!workspace.retainedExportReady) }
            }
        }.padding(12).background(.quaternary.opacity(0.5))
        Divider()
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = (workspace.current?.title ?? "Note") + " retained.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try workspace.exportRetainedNote(to: url) } catch { workspace.issue = error.localizedDescription }
    }
}
