import Foundation
import Network

/// Bind only to loopback. Never expose the OAuth callback to the LAN.
@MainActor
public final class ChatGPTLoopback {
  private var listener: NWListener?
  private var connections: [UUID: NWConnection] = [:]
  private var ready: CheckedContinuation<URL, Error>?
  public var onCallback: ((URL) -> Bool)?
  public var onFailure: ((Error) -> Void)?
  public private(set) var redirectURI: URL?

  public init() {}

  public func start() async throws -> URL {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let server = try NWListener(using: parameters)
    listener = server
    return try await withCheckedThrowingContinuation { continuation in
      ready = continuation
      server.stateUpdateHandler = { [weak self] state in
        Task { @MainActor in
          guard let self else { return }
          switch state {
          case .ready:
            guard let port = server.port else { self.fail(ChatGPTError.message("The local sign-in listener has no port.")); return }
            let url = URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback")!
            self.redirectURI = url
            self.ready?.resume(returning: url); self.ready = nil
          case .failed:
            self.fail(ChatGPTError.message("The local sign-in listener could not start."))
          case .cancelled:
            self.ready?.resume(throwing: CancellationError()); self.ready = nil
          default: break
          }
        }
      }
      server.newConnectionHandler = { [weak self] connection in
        Task { @MainActor in self?.accept(connection) }
      }
      server.start(queue: .main)
    }
  }

  public func stop() {
    listener?.cancel(); listener = nil
    for connection in connections.values { connection.cancel() }
    connections.removeAll()
    ready?.resume(throwing: CancellationError()); ready = nil
    onCallback = nil; onFailure = nil
  }

  private func fail(_ error: Error) {
    ready?.resume(throwing: error); ready = nil
    onFailure?(error)
    stop()
  }

  private func accept(_ connection: NWConnection) {
    guard connections.count < 16 else { connection.cancel(); return }
    let id = UUID()
    connections[id] = connection
    connection.start(queue: .main)
    receive(connection, id: id, buffer: Data())
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 10_000_000_000)
      self?.connections.removeValue(forKey: id)?.cancel()
    }
  }

  private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
      Task { @MainActor in
        guard let self, self.connections[id] != nil else { return }
        let next = buffer + (data ?? Data())
        guard next.count <= 16_384, error == nil else { self.reply(connection, id: id, accepted: false); return }
        if let boundary = next.range(of: Data("\r\n\r\n".utf8)) {
          let header = String(decoding: next[..<boundary.lowerBound], as: UTF8.self)
          let url = Self.callbackURL(header: header, redirectURI: self.redirectURI)
          let accepted = url.map { self.onCallback?($0) ?? false } ?? false
          self.reply(connection, id: id, accepted: accepted)
        } else if complete {
          self.reply(connection, id: id, accepted: false)
        } else {
          self.receive(connection, id: id, buffer: next)
        }
      }
    }
  }

  /// The HTTP boundary rejects absolute URLs, other paths and unexpected Host headers.
  static func callbackURL(header: String, redirectURI: URL?) -> URL? {
    guard let redirectURI, let port = redirectURI.port else { return nil }
    let lines = header.components(separatedBy: "\r\n")
    let request = lines.first?.split(separator: " ").map(String.init) ?? []
    let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }
    guard request.count == 3, request[0] == "GET", ["HTTP/1.1", "HTTP/1.0"].contains(request[2]),
          request[1].hasPrefix("/auth/callback?"), hosts.count == 1,
          hosts[0].dropFirst(5).trimmingCharacters(in: .whitespaces) == "127.0.0.1:\(port)",
          let url = URL(string: "http://127.0.0.1:\(port)\(request[1])"),
          url.path == redirectURI.path, url.fragment == nil else { return nil }
    return url
  }

  private func reply(_ connection: NWConnection, id: UUID, accepted: Bool) {
    let body = accepted ? "Sign-in received. Return to Zerus." : "This sign-in callback could not be accepted."
    let text = "HTTP/1.1 \(accepted ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
    connection.send(content: Data(text.utf8), completion: .contentProcessed { [weak self] _ in
      connection.cancel()
      Task { @MainActor in self?.connections.removeValue(forKey: id) }
    })
  }
}
