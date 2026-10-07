import Foundation
import Darwin

struct ServiceHealth {
    let runner: any CommandRunning
    func processAlive(_ pid: Int32) -> Bool { pid > 1 && (kill(pid, 0) == 0 || errno == EPERM) }
    func ready(_ instance: DatabaseInstance) -> Bool {
        guard DatabaseManager.portListening(instance.port) else { return false }
        let bin = instance.installation.prefix + "/bin/"
        switch instance.engine {
        case .postgresql:
            let tool = bin + "pg_isready"
            if FileManager.default.isExecutableFile(atPath: tool) {
                return (try? runner.run("/usr/bin/env", ["-i", "PATH=/usr/bin:/bin", "HOME=" + FileManager.default.homeDirectoryForCurrentUser.path,
                    tool, "-h", "127.0.0.1", "-p", String(instance.port), "-U", "postgres", "-d", "postgres", "-q", "-t", "1"], environment: [:]).status) == 0
            }
            return true // Native process plus a TCP listener when no client exists.
        case .mysql, .mariadb:
            let tools = instance.engine == .mariadb ? [bin + "mariadb-admin", bin + "mysqladmin"] : [bin + "mysqladmin"]
            if let tool = tools.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                return (try? runner.run(tool, ["--no-defaults", "--protocol=tcp", "--host=127.0.0.1", "--port=\(instance.port)", "--user=root", "--connect-timeout=1", "--silent", "ping"], environment: [:]).status) == 0
            }
            return true
        case .redis, .valkey:
            return exchange(port: instance.port, request: Data("*1\r\n$4\r\nPING\r\n".utf8))?.starts(with: Data("+PONG\r\n".utf8)) == true
        case .memcached:
            return exchange(port: instance.port, request: Data("version\r\n".utf8))?.starts(with: Data("VERSION ".utf8)) == true
        case .mongodb:
            // The server is started in the foreground. Process liveness and
            // TCP readiness work without adding mongosh to the app dependency.
            return true
        }
    }
    func smtpReady(_ port: Int) -> Bool {
        exchange(port: port, request: Data())?.starts(with: Data("220 ".utf8)) == true
    }
    private func exchange(port: Int, request: Data) -> Data? {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var timeout = timeval(tv_sec: 1, tv_usec: 0), noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian; address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard connected == 0 else { return nil }
        let sent = request.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
        guard sent == request.count else { return nil }
        var buffer = [UInt8](repeating: 0, count: 512)
        let count = Darwin.recv(fd, &buffer, buffer.count, 0)
        guard count > 0 else { return nil }
        return Data(buffer.prefix(count))
    }
}
