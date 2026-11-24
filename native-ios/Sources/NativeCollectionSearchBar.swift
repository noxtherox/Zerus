import SwiftUI
import UIKit

/// Keep sorting outside the editable search field, while sharing the same
/// collection controls used in Settings.
struct NativeCollectionSearchBar: View {
    @Environment(\.nativeWorkspaceChromeVisible) private var chromeVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var query: String
    let prompt: String
    let collection: NativeCollectionSettingsContext
    @State private var focused = false
    @State private var filtering = false
    /// The field updates at once; the collection filters after a short pause
    /// so each keystroke does not search every note.
    @State private var text = ""
    @State private var pending: Task<Void, Never>?
    @ScaledMetric(relativeTo: .body) private var fieldHeight: CGFloat = 44
    private var activeCount: Int { collection.filters.wrappedValue.activeCount }

    private var visible: Bool { chromeVisible || focused || filtering }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                NativeCollectionSearchField(text: $text, focused: $focused, prompt: prompt)
                    .frame(maxWidth: .infinity).frame(height: fieldHeight)
                    .background(Accent.text.opacity(0.10), in: Capsule())
                    .clipShape(Capsule())
                Button { focused = false; filtering = true } label: {
                    Image(systemName: activeCount == 0 ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 20))
                        .frame(width: max(fieldHeight, 44), height: max(fieldHeight, 44))
                        .foregroundStyle(activeCount == 0 ? Accent.text : Accent.color)
                        .background(Accent.text.opacity(0.10), in: Circle())

                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sort and filter")
                .accessibilityValue(activeCount == 0 ? "No filters applied" : "\(activeCount) applied")
                .accessibilityIdentifier("collection.search.filters")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .offset(y: visible ? 0 : -(max(fieldHeight, 44) + 24))
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: visible)
        .background {
            Button("Find") { focused = true }.keyboardShortcut("f", modifiers: .command).hidden()
        }
        .sheet(isPresented: $filtering) {
            NativeCollectionFilterView(filters: collection.filters, notes: collection.notes,
                archiveOnly: collection.archiveOnly, fileTypes: collection.fileTypes, otherFiles: collection.otherFiles)
        }
        .onDisappear { focused = false }
        .onAppear { text = query }
        .onChange(of: text) { _, value in
            pending?.cancel()
            guard !query.utf8.elementsEqual(value.utf8) else { return }
            if value.isEmpty { query = value; return }
            pending = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled, !query.utf8.elementsEqual(text.utf8) { query = text }
            }
        }
        .onChange(of: query) { _, value in if !text.utf8.elementsEqual(value.utf8) { pending?.cancel(); text = value } }
    }
}

/// UISearchBar supplies the native search accessibility role, clear button,
/// keyboard and editing behavior inside the custom control row.
private struct NativeCollectionSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let prompt: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> SearchBar {
        let bar = SearchBar(frame: .zero)
        bar.delegate = context.coordinator
        bar.searchBarStyle = .minimal
        bar.backgroundImage = UIImage()
        bar.returnKeyType = .search
        bar.autocapitalizationType = .none
        bar.autocorrectionType = .no
        bar.searchTextField.clearButtonMode = .whileEditing
        bar.searchTextField.adjustsFontForContentSizeCategory = true
        bar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return bar
    }
    func updateUIView(_ bar: SearchBar, context: Context) {
        context.coordinator.parent = self
        if bar.text != text { bar.text = text }
        let field = bar.searchTextField
        field.font = .preferredFont(forTextStyle: .body)
        field.backgroundColor = .clear
        field.textColor = NativeThemeUIKit.text
        field.tintColor = NativeThemeUIKit.accent
        field.attributedPlaceholder = NSAttributedString(string: prompt, attributes: [.foregroundColor: NativeThemeUIKit.secondaryText])
        field.accessibilityLabel = prompt
        field.accessibilityIdentifier = "collection.search"
        if focused, !field.isFirstResponder, bar.window != nil { field.becomeFirstResponder() }
        else if !focused, field.isFirstResponder { field.resignFirstResponder() }
    }
    final class SearchBar: UISearchBar, UIGestureRecognizerDelegate {
        private weak var dismissalWindow: UIWindow?
        private lazy var outsideTap: UITapGestureRecognizer = {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            return gesture
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            dismissalWindow?.removeGestureRecognizer(outsideTap)
            dismissalWindow = window
            window?.addGestureRecognizer(outsideTap)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            searchTextField.isFirstResponder && !bounds.contains(touch.location(in: self))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func dismissKeyboard() { searchTextField.resignFirstResponder() }


        override func layoutSubviews() {
            super.layoutSubviews()
            // The surrounding SwiftUI row owns spacing. Use the same bounds
            // for the native field so it aligns with the adjacent 44pt button.
            if let container = searchTextField.superview {
                searchTextField.frame = convert(bounds, to: container)
                searchTextField.layer.cornerRadius = bounds.height / 2
                searchTextField.layer.cornerCurve = .continuous
                searchTextField.clipsToBounds = true
            }
        }
    }
    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: NativeCollectionSearchField
        init(parent: NativeCollectionSearchField) { self.parent = parent }
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { parent.text = searchText }
        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) { if !parent.focused { parent.focused = true } }
        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) { if parent.focused { parent.focused = false } }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
    }
}

/// Reserve space only at the beginning of the list, then float above its
/// scrolling content. Hiding this overlay never changes scroll-view insets.
extension View {
    func nativeCollectionSearch(query: Binding<String>, prompt: String, collection: NativeCollectionSettingsContext) -> some View {
        modifier(NativeFloatingCollectionSearch(query: query, prompt: prompt, collection: collection))
    }
}

private struct NativeFloatingCollectionSearch: ViewModifier {
    @Binding var query: String
    let prompt: String
    let collection: NativeCollectionSettingsContext
    @ScaledMetric(relativeTo: .body) private var fieldHeight: CGFloat = 44

    func body(content: Content) -> some View {
        content
            .contentMargins(.top, max(fieldHeight, 44) + 24, for: .scrollContent)
            .overlay(alignment: .top) {
                NativeCollectionSearchBar(query: $query, prompt: prompt, collection: collection)
            }
            .clipped()
    }
}
