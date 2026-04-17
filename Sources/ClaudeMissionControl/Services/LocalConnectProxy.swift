// Sources/ClaudeMissionControl/Services/LocalConnectProxy.swift
import Foundation
import Network
import os.log

/// A minimal HTTP CONNECT proxy listening on 127.0.0.1, used to route WKWebView traffic through
/// pure TCP so the request never tries HTTP/3 (QUIC) — QUIC fails over VPN tunnels with small MTU
/// (sendmsg returns EMSGSIZE because a 1252-byte Initial packet exceeds the tunnel). WebKit has
/// no public or private H3 toggle in this macOS release, so we bypass it at the network layer:
/// WKWebView opens a CONNECT tunnel to us, we dial the target with `NWParameters.tcp`, then pump
/// bytes in both directions. TLS is still end-to-end (browser → Cloudflare), so CF's JA3 check
/// continues to see a real browser fingerprint.
final class LocalConnectProxy: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.claudemissioncontrol", category: "connect-proxy")

    private var listener: NWListener?
    private var _port: UInt16 = 0
    private let portLock = NSLock()
    private let queue = DispatchQueue(label: "com.claudemissioncontrol.connect-proxy")

    var port: UInt16 {
        portLock.lock(); defer { portLock.unlock() }
        return _port
    }

    init() {}

    /// Starts the listener. Returns once `port` is assigned (or throws).
    func start() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = ResumeOnce()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let p = listener.port {
                        self?.portLock.lock()
                        self?._port = p.rawValue
                        self?.portLock.unlock()
                    }
                    resumed.fire { cont.resume() }
                case .failed(let err):
                    resumed.fire { cont.resume(throwing: err) }
                case .cancelled:
                    resumed.fire { cont.resume(throwing: CancellationError()) }
                default: break
                }
            }
            listener.start(queue: self.queue)
        }
        Self.log.debug("LocalConnectProxy listening on 127.0.0.1:\(self.port, privacy: .public)")
    }

    private func accept(_ client: NWConnection) {
        client.start(queue: queue)
        readRequestLine(client, accumulated: Data()) { [weak self] result in
            switch result {
            case .failure(let err):
                Self.log.error("proxy: read CONNECT failed: \(err.localizedDescription, privacy: .public)")
                client.cancel()
            case .success(let (host, port)):
                Self.log.debug("proxy: CONNECT \(host, privacy: .public):\(port, privacy: .public)")
                self?.dialUpstream(host: host, port: port, client: client)
            }
        }
    }

    /// Reads from `client` until the double CRLF that ends HTTP request headers, then parses the
    /// request line `CONNECT host:port HTTP/1.1`. Deliberately lax — we trust the client (our own
    /// WKWebView).
    private func readRequestLine(
        _ client: NWConnection,
        accumulated: Data,
        completion: @escaping (Result<(String, UInt16), Error>) -> Void
    ) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isEOF, err in
            if let err {
                completion(.failure(err)); return
            }
            var buf = accumulated
            if let data { buf.append(data) }
            if buf.range(of: Data("\r\n\r\n".utf8)) != nil {
                let head = buf
                guard let text = String(data: head, encoding: .utf8) else {
                    completion(.failure(ProxyError.badRequest)); return
                }
                guard let firstLine = text.split(separator: "\r\n").first else {
                    completion(.failure(ProxyError.badRequest)); return
                }
                let parts = firstLine.split(separator: " ")
                guard parts.count >= 2, parts[0] == "CONNECT" else {
                    completion(.failure(ProxyError.notConnect)); return
                }
                let hostPort = parts[1].split(separator: ":")
                guard hostPort.count == 2, let p = UInt16(hostPort[1]) else {
                    completion(.failure(ProxyError.badRequest)); return
                }
                completion(.success((String(hostPort[0]), p)))
                return
            }
            if isEOF || buf.count > 8192 {
                completion(.failure(ProxyError.badRequest)); return
            }
            self.readRequestLine(client, accumulated: buf, completion: completion)
        }
    }

    private func dialUpstream(host: String, port: UInt16, client: NWConnection) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        // NWParameters.tcp guarantees TCP transport — no QUIC negotiation regardless of what the
        // DNS HTTPS record advertises. This is the whole point of this proxy.
        let upstream = NWConnection(to: endpoint, using: .tcp)
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Self.log.debug("proxy: upstream ready to \(host, privacy: .public)")
                client.send(
                    content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8),
                    completion: .contentProcessed { err in
                        if let err {
                            Self.log.error("proxy: failed to ack CONNECT: \(err.localizedDescription, privacy: .public)")
                            client.cancel(); upstream.cancel(); return
                        }
                        self.pump(from: client, to: upstream, label: "c->u")
                        self.pump(from: upstream, to: client, label: "u->c")
                    }
                )
            case .failed(let err):
                Self.log.error("proxy: upstream failed: \(err.localizedDescription, privacy: .public)")
                client.send(
                    content: Data("HTTP/1.1 502 Bad Gateway\r\n\r\n".utf8),
                    completion: .contentProcessed { _ in client.cancel() }
                )
            case .cancelled:
                client.cancel()
            default: break
            }
        }
        upstream.start(queue: queue)
    }

    /// Recursive byte pump. Each `receive` completion re-enqueues another receive until EOF.
    /// macOS caps the recursion via the queue, so this doesn't blow the stack.
    private func pump(from: NWConnection, to: NWConnection, label: String) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isEOF, err in
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { sendErr in
                    if let sendErr {
                        Self.log.error("proxy[\(label, privacy: .public)] send failed: \(sendErr.localizedDescription, privacy: .public)")
                        from.cancel(); to.cancel(); return
                    }
                    if isEOF {
                        to.send(content: nil, contentContext: .finalMessage, isComplete: true,
                                completion: .contentProcessed { _ in })
                        return
                    }
                    self?.pump(from: from, to: to, label: label)
                })
            } else if isEOF || err != nil {
                to.send(content: nil, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in })
            } else {
                self?.pump(from: from, to: to, label: label)
            }
        }
    }

    enum ProxyError: Error {
        case badRequest
        case notConnect
    }
}

/// Ensures a `CheckedContinuation` is resumed at most once — `NWListener.stateUpdateHandler`
/// can fire multiple terminal states.
private final class ResumeOnce: @unchecked Sendable {
    private var fired = false
    private let lock = NSLock()
    func fire(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        if fired { return }
        fired = true
        body()
    }
}
