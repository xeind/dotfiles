// Receives Karabiner send_user_command datagrams and appends one usage line per
// Hyper press: local time to the second, layer, key, tab-separated. The format is
// the one the old `printf ... >> usage.log` shell command wrote.
//
// Usage: hyperdash-usage-receiver [SOCKET_PATH [LOG_PATH]]
// Defaults: ~/.local/state/karabiner/usage.sock and ~/.local/state/karabiner/usage.log
// Payload:  {"layer":"w","key":"u"}

import Darwin
import Foundation

let stateDirectory = "\(NSHomeDirectory())/.local/state/karabiner"
let arguments = CommandLine.arguments
let socketPath = arguments.count > 1 ? arguments[1] : "\(stateDirectory)/usage.sock"
let logPath = arguments.count > 2 ? arguments[2] : "\(stateDirectory)/usage.log"

func report(_ message: String) {
    FileHandle.standardError.write(Data("hyperdash-usage-receiver: \(message)\n".utf8))
}

func fail(_ message: String) -> Never {
    report(message)
    exit(1)
}

func socketPathExists() -> Bool {
    var info = stat()
    return lstat(socketPath, &info) == 0
}

/// Bind a fresh datagram socket at socketPath, replacing any stale file.
func bindSocket() -> Int32 {
    let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
    guard fd >= 0 else { fail("socket failed: \(String(cString: strerror(errno)))") }
    unlink(socketPath)

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let path = Array(socketPath.utf8CString)
    guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        fail("socket path is longer than sun_path allows: \(socketPath)")
    }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        path.withUnsafeBytes { buffer.copyMemory(from: $0) }
    }
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else { fail("bind \(socketPath) failed: \(String(cString: strerror(errno)))") }
    return fd
}

/// Local time as `date +%FT%T` prints it.
func timestamp() -> String {
    var now = time(nil)
    var parts = tm()
    localtime_r(&now, &parts)
    var buffer = [UInt8](repeating: 0, count: 32)
    let length = strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S", &parts)
    return String(decoding: buffer[0..<length], as: UTF8.self)
}

/// Karabiner key codes: lower-case letters, digits and underscores.
func isKeyCode(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95 }
}

/// Append one line. The log is append-only and never renamed (RETENTION.md),
/// so opening it per line with O_APPEND matches what `>>` did.
func append(_ line: String) {
    let fd = open(logPath, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    guard fd >= 0 else {
        report("open \(logPath) failed: \(String(cString: strerror(errno)))")
        return
    }
    let bytes = Array(line.utf8)
    if write(fd, bytes, bytes.count) != bytes.count {
        report("write \(logPath) failed: \(String(cString: strerror(errno)))")
    }
    close(fd)
}

func handle(_ data: Data) {
    guard
        let object = try? JSONSerialization.jsonObject(with: data),
        let payload = object as? [String: Any],
        let layer = payload["layer"] as? String, isKeyCode(layer),
        let key = payload["key"] as? String, isKeyCode(key)
    else {
        report("rejected payload: \(String(decoding: data.prefix(200), as: UTF8.self))")
        return
    }
    append("\(timestamp())\t\(layer)\t\(key)\n")
}

signal(SIGPIPE, SIG_IGN)
var fd = bindSocket()
var buffer = [UInt8](repeating: 0, count: 32 * 1024)

while true {
    // Rebind if something deleted the socket file; Karabiner could no longer reach us.
    if !socketPathExists() {
        close(fd)
        fd = bindSocket()
        report("socket file was missing; bound it again")
    }
    var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    let ready = poll(&poller, 1, 1000)
    if ready < 0 {
        if errno == EINTR { continue }
        fail("poll failed: \(String(cString: strerror(errno)))")
    }
    if ready == 0 { continue }

    let count = recv(fd, &buffer, buffer.count, 0)
    if count < 0 {
        if errno == EINTR { continue }
        fail("recv failed: \(String(cString: strerror(errno)))")
    }
    if count > 0 { handle(Data(buffer[0..<count])) }
}
