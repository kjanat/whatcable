import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// A deliberately tiny, single-threaded HTTP/1.1 server built directly on
/// Glibc sockets — no third-party dependency, since the Linux GUI must build
/// from the same `swift build` as the CLI. It binds to loopback only (the
/// dashboard is for the local user, never the network) and handles one
/// request at a time, which is plenty for a status page polled every couple
/// of seconds.
final class HTTPServer {
    struct Request {
        let method: String
        let path: String
    }

    struct Response {
        let status: String          // e.g. "200 OK"
        let contentType: String
        let body: String

        static func html(_ body: String) -> Response {
            Response(status: "200 OK", contentType: "text/html; charset=utf-8", body: body)
        }
        static func json(_ body: String) -> Response {
            Response(status: "200 OK", contentType: "application/json; charset=utf-8", body: body)
        }
        static func notFound() -> Response {
            Response(status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: "Not found")
        }
    }

    private let port: UInt16
    private let handler: (Request) -> Response
    private var serverFD: Int32 = -1

    init(port: UInt16, handler: @escaping (Request) -> Response) {
        self.port = port
        self.handler = handler
    }

    /// Bind + listen. Throws if the socket can't be created or bound (e.g. the
    /// port is already in use).
    func start() throws {
        #if canImport(Glibc)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { throw ServerError.socket(errno) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian                       // network byte order
        addr.sin_addr = in_addr(s_addr: UInt32(0x7F00_0001).bigEndian)  // 127.0.0.1

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { close(fd); throw ServerError.bind(port, errno) }
        guard listen(fd, 16) == 0 else { close(fd); throw ServerError.listen(errno) }
        serverFD = fd
        #else
        throw ServerError.unsupportedPlatform
        #endif
    }

    /// Accept connections forever, serving each synchronously.
    func serveForever() {
        #if canImport(Glibc)
        while true {
            let client = accept(serverFD, nil, nil)
            guard client >= 0 else { continue }
            defer { close(client) }
            guard let request = readRequest(client) else { continue }
            write(client, response: handler(request))
        }
        #endif
    }

    // MARK: - Connection handling

    #if canImport(Glibc)
    /// Read just enough of the request to extract the method and path. The
    /// request line is the first line; for a status dashboard we don't need
    /// headers or a body.
    private func readRequest(_ client: Int32) -> Request? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = read(client, &buffer, buffer.count)
        guard n > 0 else { return nil }
        let text = String(decoding: buffer[0..<n], as: UTF8.self)
        // The request line is the first line; strip a trailing CR if present.
        guard let rawLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return nil
        }
        let line = rawLine.hasSuffix("\r") ? rawLine.dropLast() : rawLine
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return Request(method: String(parts[0]), path: String(parts[1]))
    }

    private func write(_ client: Int32, response: Response) {
        let bodyBytes = Array(response.body.utf8)
        let head = """
        HTTP/1.1 \(response.status)\r
        Content-Type: \(response.contentType)\r
        Content-Length: \(bodyBytes.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        var out = Array(head.utf8)
        out.append(contentsOf: bodyBytes)
        out.withUnsafeBytes { raw in
            var sent = 0
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            while sent < out.count {
                let w = Glibc.write(client, base + sent, out.count - sent)
                if w <= 0 { break }
                sent += w
            }
        }
    }
    #endif

    enum ServerError: Error, CustomStringConvertible {
        case socket(Int32)
        case bind(UInt16, Int32)
        case listen(Int32)
        case unsupportedPlatform

        var description: String {
            switch self {
            case .socket(let e):       return "could not create socket (errno \(e))"
            case .bind(let p, let e):  return "could not bind to 127.0.0.1:\(p) (errno \(e)) — is it already in use?"
            case .listen(let e):       return "could not listen (errno \(e))"
            case .unsupportedPlatform: return "the local GUI server is only supported on Linux"
            }
        }
    }
}
