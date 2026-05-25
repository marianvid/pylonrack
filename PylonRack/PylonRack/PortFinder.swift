import Foundation

func findFreePort(startingFrom preferred: Int) -> Int {
    let start = max(1024, min(65534, preferred))
    for port in start...min(start + 200, 65535) {
        if portIsFree(port) { return port }
    }
    return findAnyFreePort() ?? preferred
}

private func portIsFree(_ port: Int) -> Bool {
    let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else { return false }
    defer { Darwin.close(sock) }

    var reuseFlag: Int32 = 1
    Darwin.setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuseFlag,
                      socklen_t(MemoryLayout<Int32>.size))

    var addr        = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port   = in_port_t(port).bigEndian
    addr.sin_addr   = in_addr(s_addr: INADDR_ANY)
    addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)

    return withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
        }
    }
}

private func findAnyFreePort() -> Int? {
    let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else { return nil }
    defer { Darwin.close(sock) }

    var addr        = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port   = 0
    addr.sin_addr   = in_addr(s_addr: INADDR_ANY)
    addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)

    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bound == 0 else { return nil }

    var result = sockaddr_in()
    var len    = socklen_t(MemoryLayout<sockaddr_in>.size)
    withUnsafeMutablePointer(to: &result) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.getsockname(sock, $0, &len)
        }
    }
    return Int(in_port_t(bigEndian: result.sin_port))
}
