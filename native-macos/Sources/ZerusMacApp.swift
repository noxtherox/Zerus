import SwiftUI
import AppKit

@main struct ZerusMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup(id: "workspace") { MacWindow() }.handlesExternalEvents(matching: ["*"]).defaultSize(width: 1400, height: 850).windowResizability(.contentMinSize).windowStyle(.titleBar).commands { MacCommands() }
        Settings { MacZoomPresentation { MacSettingsView() }.modifier(MacThemeHost()) }
    }
}
struct MacWindow: View {
    // StateObject evaluates its initializer once per window; the workspace
    // itself is observed through Observation.
    @StateObject private var holder = MacWorkspaceHolder()
    private var store: MacWorkspace { holder.store }
    @AppStorage("zerus.mac.appearance") private var appearance = "light"
    var body: some View { MacZoomViewport { MacWorkspaceView(store: store) }.frame(minWidth: 600, minHeight: 620).modifier(MacThemeHost()).disabled(store.preparingToClose).background(MacWindowCloseProtector(workspace: store).frame(width: 0, height: 0)).preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil) }
}
@MainActor final class MacWorkspaceHolder: ObservableObject { let store = MacWorkspace() }
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) { MacDesktopFileEvents.receive(urls) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.activate(ignoringOtherApps: true); MacUpdates.shared.start() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let stores = MacWorkspace.windows.compactMap(\.value)
        guard !stores.isEmpty || MacChatController.hasLiveSessions || !MacHTMLDownloads.shared.active.isEmpty else { return .terminateNow }
        Task {
            var saved = await MacChatController.prepareAllToQuit()
            for store in stores { if !(await store.prepareToQuit()) { saved = false } }
            if saved { saved = await MacHTMLDownloads.shared.prepareToQuit() }
            if !saved { for store in stores { store.agentController?.cancelLeaving() } }
            NSApp.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}
extension Notification.Name { static let macSaveBeforeQuit = Notification.Name("zerus.mac.saveBeforeQuit") }
@MainActor enum MacNoteFind {
    static func show(in view: NSTextView? = nil) {
        let sender = NSMenuItem()
        sender.tag = NSTextFinder.Action.showFindInterface.rawValue
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: view, from: sender)
    }
}
extension FocusedValues {
    /// The focused window's workspace, for menu commands.
    @Entry var macWorkspace: MacWorkspace?
}
struct MacCommands: Commands {
    @FocusedValue(\.macWorkspace) var store: MacWorkspace?
    @Environment(\.openWindow) private var openWindow
    private var locked: Bool { store == nil || store?.busy == true || store?.preparingToClose == true }
    private var tabsLocked: Bool { locked || store?.editorSheetActive == true || store?.tabs.isEmpty != false }
    private func closeWindow() {
        let window = NSApp.keyWindow
        (window?.sheetParent ?? window)?.performClose(nil)
    }
    var body: some Commands {
        CommandGroup(after: .appInfo) { MacCheckForUpdates() }
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "workspace") }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Note") { Task { await store?.createNote() } }.keyboardShortcut("n").disabled(store?.root == nil || locked)
            Button("Open Vault…") { store?.chooseVault() }.keyboardShortcut("o").disabled(locked)
            Button("Import Desktop Settings…") { store?.importDesktopSettings() }.disabled(locked || store?.editorSheetActive == true)
            Button("Note Recovery Drafts…") { store?.showNoteRecovery = true }.disabled(store?.root == nil || locked)
            Button("HTML Downloads…") { MacHTMLDownloads.shared.show() }
        }
        CommandGroup(replacing: .saveItem) { Button("Save") { Task { await store?.saveFocusedDocument() } }.keyboardShortcut("s").disabled(locked) }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { store?.presentPrint() }.keyboardShortcut("p").disabled(locked || store?.canPrintCurrentNote != true)
        }
        CommandGroup(after: .saveItem) {
            // ⌘W closes the active tab like Safari; with no tabs it closes the window.
            Button("Close Tab") {
                guard let store, !store.tabs.isEmpty else { return closeWindow() }
                guard let tab = store.activeTab, !store.pinnedTabs.contains(tab) else { return NSSound.beep() }
                Task { await store.closeTab(tab) }
            }.keyboardShortcut("w").disabled(store?.editorSheetActive == true || store?.busy == true)
            Button("Close Window") { closeWindow() }.keyboardShortcut("w", modifiers: [.command, .shift]).disabled(store?.editorSheetActive == true)
        }
        CommandGroup(before: .windowList) {
            Button("Show Next Tab") { Task { await store?.cycleTab(by: 1) } }.keyboardShortcut(.tab, modifiers: .control).disabled(tabsLocked)
            Button("Show Previous Tab") { Task { await store?.cycleTab(by: -1) } }.keyboardShortcut(.tab, modifiers: [.control, .shift]).disabled(tabsLocked)
            ForEach(1...9, id: \.self) { number in
                // ⌘9 always selects the last tab, as in Safari.
                Button(number == 9 ? "Select Last Tab" : "Select Tab \(number)") { Task { await store?.selectTab(at: number == 9 ? Int.max : number - 1) } }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command).disabled(tabsLocked)
            }
            Divider()
        }
        CommandGroup(after: .pasteboard) {
            Button("Paste and Match Style") { NSApp.sendAction(#selector(NSTextView.pasteAsPlainText(_:)), to: nil, from: nil) }
                .keyboardShortcut("v", modifiers: [.command, .option, .shift])
        }
        CommandGroup(after: .textEditing) {
            Button("Bold") { NotificationCenter.default.post(name: .macEditorAction, object: "bold") }.keyboardShortcut("b")
            Button("Italic") { NotificationCenter.default.post(name: .macEditorAction, object: "italic") }.keyboardShortcut("i")
            Button("Underline") { NotificationCenter.default.post(name: .macEditorAction, object: "underline") }.keyboardShortcut("u")
            Button("Insert or Edit Link…") { NotificationCenter.default.post(name: .macEditorAction, object: "link") }.keyboardShortcut("k")
            Button("Toggle Checklist Item") { NotificationCenter.default.post(name: .macEditorAction, object: "toggleChecklist") }.disabled(store?.selection == nil && store?.external.selected == nil)
            Menu("Paragraph style") {
                Button("Paragraph") { NotificationCenter.default.post(name: .macEditorAction, object: "paragraph") }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") { NotificationCenter.default.post(name: .macEditorAction, object: "h\(level)") }
                        .keyboardShortcut(KeyEquivalent(Character(String(level))), modifiers: [.command, .option])
                }
            }
        }
        CommandGroup(after: .toolbar) {
            Button("Search Everything") { store?.showSearch = true }.keyboardShortcut("f").disabled(locked)
            Button("Find in Note") { MacNoteFind.show() }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Show Inspector") { store?.inspectorRequest += 1 }.keyboardShortcut("i", modifiers: [.command, .option]).disabled(locked || store?.selection == nil)
            Button("AI Chat") { store?.showChat = true }.keyboardShortcut("j").disabled(locked)
        }
    }
}
