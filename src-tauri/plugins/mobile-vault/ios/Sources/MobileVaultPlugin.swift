import SwiftRs
import Tauri
import UIKit
import UniformTypeIdentifiers
import WebKit

final class MobileVaultPlugin: Plugin, UIDocumentPickerDelegate {
  private let bookmarkKey = "grimoire.mobileVaultBookmark.v1"
  private let externalBookmarksKey = "grimoire.mobileExternalBookmarks.v1"
  private var activeURL: URL?
  private var activeAccess = false
  private var activeExternalURLs: [String: URL] = [:]
  private var pendingPickerInvoke: Invoke?
  private var pendingPickerKind: PickerKind?
  private var documentController: UIDocumentInteractionController?
  private var webviewOffsetObservation: NSKeyValueObservation?

  @objc public override func load(webview: WKWebView) {
    let appBackground = UIColor(red: 28 / 255, green: 29 / 255, blue: 30 / 255, alpha: 1)
    webview.overrideUserInterfaceStyle = .dark
    webview.backgroundColor = appBackground
    webview.scrollView.backgroundColor = appBackground
    webview.scrollView.contentInsetAdjustmentBehavior = .never
    webview.scrollView.contentInset = .zero
    webview.scrollView.bounces = false
    webviewOffsetObservation = webview.scrollView.observe(
      \.contentOffset,
      options: [.new]
    ) { scrollView, _ in
      guard scrollView.contentOffset != .zero else { return }
      scrollView.setContentOffset(.zero, animated: false)
    }
    manager.viewController?.view.backgroundColor = appBackground
    _ = try? restoreBookmark()
    restoreExternalBookmarks()
  }

  deinit {
    webviewOffsetObservation?.invalidate()
    stopActiveAccess()
    stopExternalAccess()
  }

  @objc public func pickVaultFolder(_ invoke: Invoke) {
    guard beginPicker(invoke, kind: .vault) else {
      invoke.reject("A vault picker is already open")
      return
    }

    DispatchQueue.main.async {
      guard let viewController = self.manager.viewController else {
        self.pendingPickerInvoke = nil
        self.pendingPickerKind = nil
        invoke.reject("The iOS document browser is unavailable")
        return
      }

      let picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [UTType.folder],
        asCopy: false
      )
      picker.delegate = self
      picker.allowsMultipleSelection = false
      picker.modalPresentationStyle = .fullScreen
      viewController.present(picker, animated: true)
    }
  }

  @objc public func pickExternalNotes(_ invoke: Invoke) {
    let markdown = UTType(filenameExtension: "md") ?? .plainText
    presentFilePicker(invoke, kind: .externalNotes, contentTypes: [markdown, .plainText], multiple: true)
  }

  @objc public func pickFiles(_ invoke: Invoke) {
    presentFilePicker(invoke, kind: .files, contentTypes: [.item], multiple: false)
  }

  @objc public func openFile(_ invoke: Invoke) {
    do {
      let request = try invoke.parseArgs(OpenFileRequest.self)
      let url = URL(fileURLWithPath: request.path)
      DispatchQueue.main.async {
        guard let view = self.manager.viewController?.view else {
          invoke.reject("The iOS document browser is unavailable")
          return
        }
        let controller = UIDocumentInteractionController(url: url)
        self.documentController = controller
        if controller.presentOpenInMenu(from: view.bounds, in: view, animated: true) {
          invoke.resolve()
        } else {
          self.documentController = nil
          invoke.reject("No app on this device can open that file")
        }
      }
    } catch {
      invoke.reject("Could not open that file: \(error.localizedDescription)")
    }
  }

  @objc public func restoreVaultFolder(_ invoke: Invoke) {
    do {
      guard let url = try restoreBookmark() else {
        invoke.resolve(["vault": NSNull()])
        return
      }
      invoke.resolve(response(for: url))
    } catch {
      UserDefaults.standard.removeObject(forKey: bookmarkKey)
      stopActiveAccess()
      invoke.reject("Could not restore the selected vault: \(error.localizedDescription)")
    }
  }

  @objc public func clearVaultFolder(_ invoke: Invoke) {
    UserDefaults.standard.removeObject(forKey: bookmarkKey)
    stopActiveAccess()
    invoke.resolve()
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let invoke = pendingPickerInvoke else { return }
    pendingPickerInvoke = nil
    let pickerKind = pendingPickerKind
    pendingPickerKind = nil

    guard !urls.isEmpty else {
      resolveCancelled(invoke, kind: pickerKind)
      return
    }

    if pickerKind != .vault {
      do {
        try urls.forEach(activateExternal)
        saveExternalBookmarks()
        invoke.resolve([
          "files": urls.map { ["path": $0.path, "name": $0.lastPathComponent] }
        ])
      } catch {
        invoke.reject("Could not open the selected file: \(error.localizedDescription)")
      }
      return
    }

    guard let url = urls.first else { return }
    do {
      try activate(url)
      let values = try url.resourceValues(forKeys: [.isDirectoryKey])
      guard values.isDirectory == true else {
        stopActiveAccess()
        invoke.reject("Please select a folder for your Zerus vault")
        return
      }
      try saveBookmark(for: url)
      invoke.resolve(response(for: url))
    } catch {
      stopActiveAccess()
      invoke.reject("Could not open the selected vault: \(error.localizedDescription)")
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let invoke = pendingPickerInvoke {
      resolveCancelled(invoke, kind: pendingPickerKind)
    }
    pendingPickerInvoke = nil
    pendingPickerKind = nil
  }

  private func beginPicker(_ invoke: Invoke, kind: PickerKind) -> Bool {
    guard pendingPickerInvoke == nil else { return false }
    pendingPickerInvoke = invoke
    pendingPickerKind = kind
    return true
  }

  private func presentFilePicker(
    _ invoke: Invoke,
    kind: PickerKind,
    contentTypes: [UTType],
    multiple: Bool
  ) {
    guard beginPicker(invoke, kind: kind) else {
      invoke.reject("A file picker is already open")
      return
    }
    DispatchQueue.main.async {
      guard let viewController = self.manager.viewController else {
        self.pendingPickerInvoke = nil
        self.pendingPickerKind = nil
        invoke.reject("The iOS document browser is unavailable")
        return
      }
      let picker = UIDocumentPickerViewController(
        forOpeningContentTypes: contentTypes,
        asCopy: false
      )
      picker.delegate = self
      picker.allowsMultipleSelection = multiple
      picker.modalPresentationStyle = .fullScreen
      viewController.present(picker, animated: true)
    }
  }

  private func resolveCancelled(_ invoke: Invoke, kind: PickerKind?) {
    if kind == .vault {
      invoke.resolve(["vault": NSNull()])
    } else {
      invoke.resolve(["files": []])
    }
  }

  private func response(for url: URL) -> [String: Any] {
    return [
      "vault": [
        "url": url.absoluteString,
        "name": url.lastPathComponent,
      ]
    ]
  }

  private func activate(_ url: URL) throws {
    if activeURL == url && activeAccess { return }
    stopActiveAccess()
    guard url.startAccessingSecurityScopedResource() else {
      throw MobileVaultError.securityScopeUnavailable
    }
    activeURL = url
    activeAccess = true
  }

  private func stopActiveAccess() {
    if activeAccess {
      activeURL?.stopAccessingSecurityScopedResource()
    }
    activeURL = nil
    activeAccess = false
  }

  private func saveBookmark(for url: URL) throws {
    let data = try url.bookmarkData(
      options: [],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    UserDefaults.standard.set(data, forKey: bookmarkKey)
  }

  private func restoreBookmark() throws -> URL? {
    if let activeURL, activeAccess { return activeURL }
    guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
      return nil
    }

    var isStale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
    try activate(url)
    if isStale { try saveBookmark(for: url) }
    return url
  }

  private func activateExternal(_ url: URL) throws {
    let key = url.standardizedFileURL.path
    if activeExternalURLs[key] != nil { return }
    guard url.startAccessingSecurityScopedResource() else {
      throw MobileVaultError.securityScopeUnavailable
    }
    activeExternalURLs[key] = url
  }

  private func saveExternalBookmarks() {
    let bookmarks = activeExternalURLs.values.compactMap { url in
      try? url.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    }
    UserDefaults.standard.set(bookmarks, forKey: externalBookmarksKey)
  }

  private func restoreExternalBookmarks() {
    guard let bookmarks = UserDefaults.standard.array(forKey: externalBookmarksKey) as? [Data] else {
      return
    }
    var refreshed = false
    for bookmark in bookmarks {
      var isStale = false
      guard let url = try? URL(
        resolvingBookmarkData: bookmark,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ) else { continue }
      try? activateExternal(url)
      refreshed = refreshed || isStale
    }
    if refreshed { saveExternalBookmarks() }
  }

  private func stopExternalAccess() {
    activeExternalURLs.values.forEach { $0.stopAccessingSecurityScopedResource() }
    activeExternalURLs.removeAll()
  }
}

private enum PickerKind {
  case vault
  case externalNotes
  case files
}

private struct OpenFileRequest: Decodable {
  let path: String
}

private enum MobileVaultError: LocalizedError {
  case securityScopeUnavailable

  var errorDescription: String? {
    switch self {
    case .securityScopeUnavailable:
      return "iOS did not grant access to that folder"
    }
  }
}

@_cdecl("init_plugin_mobile_vault")
func initPlugin() -> Plugin {
  return MobileVaultPlugin()
}
