import SwiftRs
import Tauri
import QuickLook
import UIKit
import UniformTypeIdentifiers
import WebKit

final class MobileVaultPlugin: Plugin, UIDocumentPickerDelegate, QLPreviewControllerDataSource {
  private let bookmarkKey = "zerus.mobileVaultBookmark.v1"
  private let externalBookmarksKey = "zerus.mobileExternalBookmarks.v1"
  private let authorizedFileCopiesKey = "zerus.authorizedFileCopies.v1"
  private var activeURL: URL?
  private var activeAccess = false
  private var activeExternalURLs: [String: URL] = [:]
  private var pendingPickerInvoke: Invoke?
  private var pendingPickerKind: PickerKind?
  private var pendingAuthorizedOpen: PendingAuthorizedOpen?
  private var previewURL: URL?
  private var previewDirectoryURL: URL?
  private var webviewOffsetObservation: NSKeyValueObservation?
  private lazy var cloudAI = CloudAIManager()
  private lazy var speechRecognizer = OnDeviceSpeechRecognizer()
  private var modernSpeechRecognizerStorage: AnyObject?

  @objc public override func load(webview: WKWebView) {
    if let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first {
      try? FileManager.default.removeItem(at: support.appending(path: "LocalAI"))
    }
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

  @objc public func pickExternalFolder(_ invoke: Invoke) {
    presentFilePicker(invoke, kind: .externalFolder, contentTypes: [.folder], multiple: false)
  }

  @objc public func openFile(_ invoke: Invoke) {
    do {
      let request = try invoke.parseArgs(OpenFileRequest.self)
      let url = try accessibleURL(forPath: request.path)
      DispatchQueue.main.async {
        guard let viewController = self.manager.viewController else {
          invoke.reject("The iOS document browser is unavailable")
          return
        }
        if request.mode == "refresh" {
          self.offerFileAuthorization(
            forPath: request.path,
            error: nil,
            from: viewController,
            invoke: invoke
          )
          return
        }
        if let cachedURL = self.authorizedFileCopy(forPath: request.path) {
          self.presentPreparedFile(
            cachedURL,
            from: viewController,
            invoke: invoke
          )
          return
        }
        let progress = self.makeFileProgressController()
        viewController.present(progress, animated: true)
        self.prepareLocalCopy(of: url) { result in
          progress.dismiss(animated: true) {
            switch result {
            case .failure(let error):
              self.offerFileAuthorization(
                forPath: request.path,
                error: error,
                from: viewController,
                invoke: invoke
              )
            case .success(let localURL):
              self.presentPreparedFile(
                localURL,
                from: viewController,
                invoke: invoke
              )
            }
          }
        }
      }
    } catch {
      invoke.reject("Could not open that file: \(error.localizedDescription)")
    }
  }

  private func presentPreparedFile(
    _ localURL: URL,
    from viewController: UIViewController,
    invoke: Invoke
  ) {
    previewURL = localURL
    let previewController = QLPreviewController()
    previewController.dataSource = self
    viewController.present(previewController, animated: true) {
      invoke.resolve()
    }
  }

  private func offerFileAuthorization(
    forPath path: String,
    error: Error?,
    from viewController: UIViewController,
    invoke: Invoke
  ) {
    var message = "Choose the current file in its storage location. Zerus will replace its saved copy and open it."
    if let error {
      message = "Your storage provider requires permission for the individual file. Zerus will keep an authorized copy for future opens.\n\n\(error.localizedDescription)"
    }
    let alert = UIAlertController(
      title: "Select this file once",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
      invoke.reject("File selection was cancelled")
    })
    alert.addAction(UIAlertAction(title: "Select File", style: .default) { _ in
      self.pendingAuthorizedOpen = PendingAuthorizedOpen(
        path: path,
        invoke: invoke
      )
      let picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [.item],
        asCopy: true
      )
      picker.delegate = self
      picker.allowsMultipleSelection = false
      picker.modalPresentationStyle = .fullScreen
      viewController.present(picker, animated: true)
    })
    viewController.present(alert, animated: true)
  }

  private func authorizedFileCopy(forPath path: String) -> URL? {
    guard let copies = UserDefaults.standard.dictionary(forKey: authorizedFileCopiesKey) as? [String: String],
          let cachedPath = copies[path] else {
      return nil
    }
    let url = URL(fileURLWithPath: cachedPath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      var updated = copies
      updated.removeValue(forKey: path)
      UserDefaults.standard.set(updated, forKey: authorizedFileCopiesKey)
      return nil
    }
    return url
  }

  private func saveAuthorizedFileCopy(_ selectedURL: URL, forPath path: String) throws -> URL {
    let baseDirectory = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("AuthorizedFiles", isDirectory: true)
    try FileManager.default.createDirectory(
      at: baseDirectory,
      withIntermediateDirectories: true
    )

    let values = try selectedURL.resourceValues(forKeys: [.contentTypeKey])
    var filename = selectedURL.lastPathComponent
    if selectedURL.pathExtension.isEmpty,
       let fileExtension = values.contentType?.preferredFilenameExtension {
      filename += ".\(fileExtension)"
    }
    let directory = baseDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent(filename)
    try FileManager.default.copyItem(at: selectedURL, to: destination)

    var copies = UserDefaults.standard.dictionary(forKey: authorizedFileCopiesKey) as? [String: String] ?? [:]
    if let oldPath = copies[path] {
      try? FileManager.default.removeItem(at: URL(fileURLWithPath: oldPath).deletingLastPathComponent())
    }
    copies[path] = destination.path
    UserDefaults.standard.set(copies, forKey: authorizedFileCopiesKey)
    return destination
  }

  private func accessibleURL(forPath path: String) throws -> URL {
    let requestedURL = URL(fileURLWithPath: path).standardizedFileURL
    let roots = [activeURL].compactMap { $0 } + Array(activeExternalURLs.values)
    let requestedPath = requestedURL.path

    guard let root = roots
      .map({ $0.standardizedFileURL })
      .filter({ requestedPath == $0.path || requestedPath.hasPrefix($0.path + "/") })
      .max(by: { $0.path.count < $1.path.count })
    else {
      throw MobileVaultError.mappedFolderAccessExpired
    }

    let relativePath = String(requestedPath.dropFirst(root.path.count))
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !relativePath.isEmpty else { return root }
    return relativePath.split(separator: "/").reduce(root) { url, component in
      url.appendingPathComponent(String(component))
    }
  }

  private func makeFileProgressController() -> UIAlertController {
    let alert = UIAlertController(
      title: "Opening file…",
      message: "Preparing a local copy…",
      preferredStyle: .alert
    )
    let spinner = UIActivityIndicatorView(style: .medium)
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.startAnimating()
    alert.view.addSubview(spinner)
    NSLayoutConstraint.activate([
      spinner.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
      spinner.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -14),
    ])
    return alert
  }

  private func prepareLocalCopy(
    of sourceURL: URL,
    completion: @escaping (Result<URL, Error>) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let coordinator = NSFileCoordinator()
      var coordinationError: NSError?
      var copyResult: Result<URL, Error>?
      coordinator.coordinate(
        readingItemAt: sourceURL,
        options: [.withoutChanges],
        error: &coordinationError
      ) { coordinatedURL in
        do {
          let values = try coordinatedURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .contentTypeKey,
          ])
          guard values.isDirectory != true else {
            throw MobileVaultError.fileUnavailable
          }

          let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZerusPreview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
          try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
          )

          var filename = coordinatedURL.lastPathComponent
          if coordinatedURL.pathExtension.isEmpty,
             let fileExtension = values.contentType?.preferredFilenameExtension {
            filename += ".\(fileExtension)"
          }
          let destination = directory.appendingPathComponent(filename)
          try FileManager.default.copyItem(at: coordinatedURL, to: destination)
          copyResult = .success(destination)
        } catch {
          copyResult = .failure(error)
        }
      }

      let result = copyResult
        ?? .failure(coordinationError ?? MobileVaultError.fileUnavailable)
      DispatchQueue.main.async {
        if case .success(let destination) = result {
          if let oldDirectory = self.previewDirectoryURL {
            try? FileManager.default.removeItem(at: oldDirectory)
          }
          self.previewDirectoryURL = destination.deletingLastPathComponent()
        }
        completion(result)
      }
    }
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    previewURL == nil ? 0 : 1
  }

  func previewController(
    _ controller: QLPreviewController,
    previewItemAt index: Int
  ) -> QLPreviewItem {
    previewURL! as NSURL
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

  @objc public func cloudAIStatus(_ invoke: Invoke) {
    invoke.resolve(cloudAI.status())
  }

  @objc public func configureCloudAI(_ invoke: Invoke) {
    do {
      let request = try invoke.parseArgs(CloudAIConfigureRequest.self)
      invoke.resolve(try cloudAI.configure(request))
    } catch {
      invoke.reject(error.localizedDescription)
    }
  }

  @objc public func generateCloudAI(_ invoke: Invoke) {
    Task {
      do {
        let request = try invoke.parseArgs(CloudAIGenerateRequest.self)
        let answer = try await cloudAI.generate(request)
        invoke.resolve(CloudAIGenerateResponse(answer: answer))
      } catch {
        invoke.reject(error.localizedDescription)
      }
    }
  }

  @objc public func startSpeechRecognition(_ invoke: Invoke) {
    Task { @MainActor in
      do {
        let request = try invoke.parseArgs(SpeechRecognitionStartRequest.self)
        let engine: String
        if #available(iOS 26.0, *) {
          try await modernSpeechRecognizer().start(localeIdentifier: request.locale)
          engine = "speechAnalyzer"
        } else {
          try await speechRecognizer.start(localeIdentifier: request.locale)
          engine = "legacy"
        }
        invoke.resolve(SpeechRecognitionStatusResponse(
          listening: true,
          onDevice: true,
          engine: engine,
          build: appBuild
        ))
      } catch {
        invoke.reject(error.localizedDescription)
      }
    }
  }

  @objc public func speechRecognitionProgress(_ invoke: Invoke) {
    Task { @MainActor in
      let progress: (listening: Bool, transcript: String)
      let engine: String
      if #available(iOS 26.0, *) {
        progress = modernSpeechRecognizer().progress()
        engine = "speechAnalyzer"
      } else {
        progress = speechRecognizer.progress()
        engine = "legacy"
      }
      invoke.resolve(SpeechRecognitionProgressResponse(
        listening: progress.listening,
        onDevice: true,
        transcript: progress.transcript,
        engine: engine,
        build: appBuild
      ))
    }
  }

  @objc public func stopSpeechRecognition(_ invoke: Invoke) {
    Task { @MainActor in
      do {
        let transcript = if #available(iOS 26.0, *) {
          try await modernSpeechRecognizer().stop()
        } else {
          try await speechRecognizer.stop()
        }
        invoke.resolve(SpeechRecognitionResponse(transcript: transcript))
      } catch {
        invoke.reject(error.localizedDescription)
      }
    }
  }

  @objc public func cancelSpeechRecognition(_ invoke: Invoke) {
    Task { @MainActor in
      if #available(iOS 26.0, *) {
        modernSpeechRecognizer().cancel()
      } else {
        speechRecognizer.cancel()
      }
      invoke.resolve()
    }
  }

  @available(iOS 26.0, *)
  private func modernSpeechRecognizer() -> ModernOnDeviceSpeechRecognizer {
    if let recognizer = modernSpeechRecognizerStorage as? ModernOnDeviceSpeechRecognizer {
      return recognizer
    }
    let recognizer = ModernOnDeviceSpeechRecognizer()
    modernSpeechRecognizerStorage = recognizer
    return recognizer
  }

  private var appBuild: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
  }

  @objc public func deviceName(_ invoke: Invoke) {
    DispatchQueue.main.async {
      invoke.resolve(["name": UIDevice.current.name])
    }
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    if let pendingOpen = pendingAuthorizedOpen {
      pendingAuthorizedOpen = nil
      guard let selectedURL = urls.first else {
        pendingOpen.invoke.reject("No file was selected")
        return
      }
      do {
        let localURL = try saveAuthorizedFileCopy(selectedURL, forPath: pendingOpen.path)
        guard let viewController = manager.viewController else {
          pendingOpen.invoke.reject("The iOS document browser is unavailable")
          return
        }
        presentPreparedFile(
          localURL,
          from: viewController,
          invoke: pendingOpen.invoke
        )
      } catch {
        pendingOpen.invoke.reject("Could not save the selected file: \(error.localizedDescription)")
      }
      return
    }

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
        try saveExternalBookmarks()
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
    } catch {
      stopActiveAccess()
      invoke.reject("Could not open the selected vault: \(error.localizedDescription)")
      return
    }

    do {
      try saveBookmark(for: url)
      invoke.resolve(response(for: url, persisted: true))
    } catch {
      // Some iCloud File Provider URLs grant usable live access but refuse to
      // create bookmark data. Keep the active scope and allow this session to
      // proceed; the user can select the folder again after a future relaunch.
      UserDefaults.standard.removeObject(forKey: bookmarkKey)
      invoke.resolve(response(
        for: url,
        persisted: false,
        bookmarkWarning: error.localizedDescription
      ))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let pendingOpen = pendingAuthorizedOpen {
      pendingAuthorizedOpen = nil
      pendingOpen.invoke.reject("File selection was cancelled")
      return
    }
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

  private func response(
    for url: URL,
    persisted: Bool = true,
    bookmarkWarning: String? = nil
  ) -> [String: Any] {
    var vault: [String: Any] = [
      "url": url.absoluteString,
      "name": url.lastPathComponent,
      "persisted": persisted,
    ]
    if let bookmarkWarning {
      vault["bookmarkWarning"] = bookmarkWarning
    }
    return [
      "vault": vault
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
      options: [.minimalBookmark],
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

  private func saveExternalBookmarks() throws {
    let bookmarks = try activeExternalURLs.values.map { url in
      try url.bookmarkData(
        options: [.minimalBookmark],
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
    var restoredURLs: [URL] = []
    for bookmark in bookmarks {
      var isStale = false
      guard let url = try? URL(
        resolvingBookmarkData: bookmark,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ) else {
        refreshed = true
        continue
      }
      do {
        try activateExternal(url)
        restoredURLs.append(url)
        refreshed = refreshed || isStale
      } catch {
        refreshed = true
      }
    }
    if refreshed {
      let validBookmarks = restoredURLs.compactMap { url in
        try? url.bookmarkData(
          options: [.minimalBookmark],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
      }
      UserDefaults.standard.set(validBookmarks, forKey: externalBookmarksKey)
    }
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
  case externalFolder
}

private struct OpenFileRequest: Decodable {
  let path: String
  let mode: String?
}

private struct PendingAuthorizedOpen {
  let path: String
  let invoke: Invoke
}

struct SpeechRecognitionStartRequest: Decodable {
  let locale: String?
}

struct SpeechRecognitionStatusResponse: Encodable {
  let listening: Bool
  let onDevice: Bool
  let engine: String
  let build: String
}

struct SpeechRecognitionResponse: Encodable {
  let transcript: String
}

struct SpeechRecognitionProgressResponse: Encodable {
  let listening: Bool
  let onDevice: Bool
  let transcript: String
  let engine: String
  let build: String
}

private enum MobileVaultError: LocalizedError {
  case securityScopeUnavailable
  case fileUnavailable
  case mappedFolderAccessExpired

  var errorDescription: String? {
    switch self {
    case .securityScopeUnavailable:
      return "iOS did not grant access to that folder"
    case .fileUnavailable:
      return "The file is not available on this device or in iCloud Drive"
    case .mappedFolderAccessExpired:
      return "Access to the mapped folder has expired. Select the folder again in Settings."
    }
  }
}

@_cdecl("init_plugin_mobile_vault")
func initPlugin() -> Plugin {
  return MobileVaultPlugin()
}
