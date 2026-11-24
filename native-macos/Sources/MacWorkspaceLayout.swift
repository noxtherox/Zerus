import SwiftUI

struct MacWorkspaceArrangement {
    let singleColumn: Bool
    let sidebar: Bool
    let canInlineSidebar: Bool
    /// The sidebar can shrink to its minimum, but a split view keeps a wider
    /// remembered width. Cap it to the space the main panes leave.
    let sidebarMaximum: CGFloat
    let collectionMaximum: CGFloat
    let collection: Bool
    let editor: Bool
    let inspector: Bool
    let canInlineInspector: Bool
    let width: CGFloat
    init(width: CGFloat, sidebar: Bool, inspector: Bool, hasNote: Bool, list: Bool, browsing: Bool, standalone: Bool = false) {
        self.width = width
        singleColumn = width < 720
        let splitList = list && !singleColumn
        collection = !standalone && (splitList || browsing || !hasNote)
        editor = !standalone && (splitList || hasNote && !browsing)
        let mainMinimum: CGFloat = standalone ? 680 : collection && editor ? 675 : editor ? 420 : 255
        canInlineSidebar = width >= mainMinimum + 201
        sidebarMaximum = min(240, max(185, width - mainMinimum - 16))
        self.sidebar = sidebar && canInlineSidebar
        collectionMaximum = list && editor ? 330 : .infinity
        canInlineInspector = !standalone && editor && hasNote && !singleColumn && width >= mainMinimum + (self.sidebar ? 185 : 0) + 256
        self.inspector = inspector && canInlineInspector
    }
}
private struct MacEditorInteractionKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var macEditorInteractionEnabled: Bool { get { self[MacEditorInteractionKey.self] } set { self[MacEditorInteractionKey.self] = newValue } }
}

/// Keep a stable editor subtree while neighbouring panes collapse. Removing it
/// on a size-class transition would discard AppKit's selection and Undo manager.
struct MacWorkspacePanes<Library: View, Collection: View, Editor: View, Inspector: View, Tabs: View>: View {
    let layout: MacWorkspaceArrangement
    var interactionEnabled = true
    let library: Library
    let collection: Collection
    let editor: Editor
    let inspector: Inspector
    let tabs: Tabs
    var body: some View {
        MacZoomSplitView {
            pane(library, visible: layout.sidebar, minimum: 185, ideal: min(218, layout.sidebarMaximum), maximum: layout.sidebarMaximum)
            VStack(spacing: 0) {
                tabs
                Divider()
                MacZoomSplitView {
                    // Keep the pane slot stable for the editor, but do not mount a
                    // hidden Gallery/board/table/calendar tree while a note is edited.
                    pane(ZStack { Color.clear; if layout.collection { collection } }, visible: layout.collection, minimum: min(255, layout.width), ideal: 310, maximum: layout.collectionMaximum)
                    pane(editor.environment(\.macEditorInteractionEnabled, layout.editor && interactionEnabled), visible: layout.editor, minimum: min(420, layout.width), ideal: 700, maximum: .infinity).layoutPriority(1)
                    pane(inspector, visible: layout.inspector, minimum: 240, ideal: 280, maximum: 360)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(1)
        }
    }
    private func pane<Content: View>(_ content: Content, visible: Bool, minimum: CGFloat, ideal: CGFloat, maximum: CGFloat) -> some View {
        content.frame(minWidth: visible ? minimum : 0, idealWidth: visible ? ideal : 0, maxWidth: visible ? maximum : 0)
            .frame(width: visible ? nil : 0).clipped().opacity(visible ? 1 : 0)
            .disabled(!visible || !interactionEnabled).allowsHitTesting(visible && interactionEnabled).accessibilityHidden(!visible || !interactionEnabled)
    }
}
