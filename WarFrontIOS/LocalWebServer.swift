import Foundation
import Darwin

/// Serves bundled web assets only on the device loopback interface.
/// HTTP origin is required for root-relative URLs and module workers.
final class LocalWebServer {
    private var listener: Int32 = -1
    private let queue = DispatchQueue(label: "warfront.http.accept", qos: .userInitiated)
    private let clients = DispatchQueue(label: "warfront.http.clients", qos: .userInitiated, attributes: .concurrent)
    private let root: URL
    private(set) var port: UInt16 = 0

    init(root: URL) { self.root = root.standardizedFileURL }

    func start() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        // Ignore EPIPE on closed WebKit connections.
        var noSigPipe: Int32 = 1
        if fd >= 0 { setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe))) }
        guard fd >= 0 else { throw ServerError.socket }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: in_addr_t(0x0100007f)) // 127.0.0.1, network byte order
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 32) == 0 else { close(fd); throw ServerError.bind }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { close(fd); throw ServerError.bind }
        port = UInt16(bigEndian: addr.sin_port)
        listener = fd
        queue.async { [weak self] in
            guard let self = self else { return }
            while self.listener >= 0 {
                let client = accept(fd, nil, nil)
                if client < 0 { break }
                self.clients.async { self.serve(client) }
            }
        }
    }

    func stop() {
        if listener >= 0 { shutdown(listener, SHUT_RDWR); close(listener); listener = -1 }
    }
    deinit { stop() }

    var url: URL { URL(string: "http://127.0.0.1:\(port)/")! }
    enum ServerError: Error { case socket, bind }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        var timeout = timeval(tv_sec: 8, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var bytes = [UInt8](repeating: 0, count: 8192)
        let n = recv(fd, &bytes, bytes.count, 0)
        guard n > 0, let request = String(bytes: bytes.prefix(n), encoding: .utf8) else { return }
        let lines = request.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { respond(fd, 400, "Bad Request"); return }
        let method = String(parts[0])
        guard method == "GET" || method == "HEAD" else { respond(fd, 405, "Method Not Allowed"); return }
        let rawPath = String(parts[1]).components(separatedBy: "?")[0]
        guard let decoded = rawPath.removingPercentEncoding,
              !decoded.contains("\\"), !decoded.contains("\0") else { respond(fd, 400, "Bad Request"); return }
        let path = decoded == "/" ? "/index.html" : decoded
        let components = path.split(separator: "/")
        guard !components.contains(".."), !components.contains("."), path.hasPrefix("/") else {
            respond(fd, 403, "Forbidden"); return
        }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"),
              FileManager.default.fileExists(atPath: file.path),
              let handle = try? FileHandle(forReadingFrom: file) else { respond(fd, 404, "Not Found"); return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let rangeLine = lines.first { $0.lowercased().hasPrefix("range:") }
        var start: UInt64 = 0
        var end = size > 0 ? size - 1 : 0
        var partial = false
        if let rangeLine = rangeLine, let value = rangeLine.split(separator: "=", maxSplits: 1).last,
           rangeLine.lowercased().contains("bytes=") {
            let limits = value.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
            if limits.count == 2, let lower = UInt64(limits[0]), lower < size {
                start = lower
                if let upper = UInt64(limits[1]) { end = min(upper, size - 1) }
                if end >= start { partial = true }
            }
        }
        let length = size == 0 ? 0 : end - start + 1
        let ext = file.pathExtension.lowercased()
        let mime: String = [
            "html":"text/html", "js":"text/javascript", "mjs":"text/javascript", "css":"text/css",
            "json":"application/json", "wasm":"application/wasm", "png":"image/png", "jpg":"image/jpeg",
            "jpeg":"image/jpeg", "webp":"image/webp", "svg":"image/svg+xml", "gif":"image/gif",
            "woff":"font/woff", "woff2":"font/woff2", "ttf":"font/ttf", "otf":"font/otf",
            "mp3":"audio/mpeg", "ogg":"audio/ogg", "wav":"audio/wav", "mp4":"video/mp4",
            "webm":"video/webm", "bin":"application/octet-stream"
        ][ext] ?? "application/octet-stream"
        var header = "HTTP/1.1 \(partial ? 206 : 200) \(partial ? "Partial Content" : "OK")\r\n"
        header += "Content-Type: \(mime)\r\nContent-Length: \(length)\r\nAccept-Ranges: bytes\r\n"
        header += "Cache-Control: public, max-age=3600\r\nConnection: close\r\n"
        if partial { header += "Content-Range: bytes \(start)-\(end)/\(size)\r\n" }
        header += "\r\n"
        writeAll(fd, Data(header.utf8))
        guard method == "GET", length > 0 else { return }
        try? handle.seek(toOffset: start)
        var remaining = length
        while remaining > 0 {
            let chunk = handle.readData(ofLength: Int(min(remaining, 65536)))
            if chunk.isEmpty { break }
            if !writeAll(fd, chunk) { break }
            remaining -= UInt64(chunk.count)
        }
    }

    @discardableResult private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return true }
            var sent = 0
            while sent < raw.count {
                let n = send(fd, base.advanced(by: sent), raw.count - sent, 0)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    private func respond(_ fd: Int32, _ code: Int, _ message: String) {
        let body = Data(message.utf8)
        let header = "HTTP/1.1 \(code) \(message)\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        writeAll(fd, Data(header.utf8)); writeAll(fd, body)
    }
}
