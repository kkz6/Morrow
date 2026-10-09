import Foundation
import Darwin
import CLaunch

/// launchd binds privileged loopback ports and gives their sockets to this
/// process running as the Mac user. No packet filtering or root worker is used.
public enum LocalGateway {
    public static func run(http: Int, https: Int, dns: Int) throws {
        try SiteSystemSetup.validatePorts(http: http, https: https, dns: dns)
        let httpFDs = try activate("http"), httpsFDs = try activate("https"), dnsTCP = try activate("dnsTCP"), dnsUDP = try activate("dnsUDP")
        let tcpSlots = DispatchSemaphore(value: 64), udpSlots = DispatchSemaphore(value: 64)
        for (fds, target) in [(httpFDs, http), (httpsFDs, https), (dnsTCP, dns)] {
            for fd in fds { blocking(fd); DispatchQueue.global(qos: .utility).async { acceptConnections(fd, target: target, slots: tcpSlots) } }
        }
        for fd in dnsUDP { blocking(fd); DispatchQueue.global(qos: .utility).async { forwardDNS(fd, target: dns, slots: udpSlots) } }
        FileHandle.standardOutput.write(Data("Morrow local gateway ready: 80, 443, TCP/UDP 53 on 127.0.0.1\n".utf8))
        dispatchMain()
    }
    private static func activate(_ name: String) throws -> [Int32] {
        var pointer: UnsafeMutablePointer<Int32>?, count = 0
        let error = name.withCString { morrow_activate_socket($0, &pointer, &count) }
        guard error == 0, let pointer, count > 0 else { throw MorrowError.message("Local gateway requires its launchd sockets (\(name), error \(error)). Run site setup first.") }
        defer { free(pointer) }; return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
    private static func blocking(_ fd: Int32) { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK) }
    private static func endpoint(_ port: Int) -> sockaddr_in {
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = UInt16(port).bigEndian; address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return address
    }
    private static func connect(_ fd: Int32, port: Int) -> Bool {
        var address = endpoint(port)
        return withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 } }
    }
    private static func acceptConnections(_ listener: Int32, target: Int, slots: DispatchSemaphore) {
        while true {
            let client = Darwin.accept(listener, nil, nil)
            if client < 0 { if errno == EINTR { continue }; _exit(1) }
            guard slots.wait(timeout: .now()) == .success else { Darwin.close(client); continue }
            DispatchQueue.global(qos: .utility).async {
                let upstream = socket(AF_INET, SOCK_STREAM, 0)
                guard upstream >= 0, connect(upstream, port: target) else { if upstream >= 0 { Darwin.close(upstream) }; Darwin.close(client); slots.signal(); return }
                var enabled: Int32 = 1
                for fd in [client, upstream] { _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) }
                let group = DispatchGroup()
                group.enter(); DispatchQueue.global(qos: .utility).async { pump(client, upstream); group.leave() }
                group.enter(); DispatchQueue.global(qos: .utility).async { pump(upstream, client); group.leave() }
                group.notify(queue: .global(qos: .utility)) { Darwin.close(client); Darwin.close(upstream); slots.signal() }
            }
        }
    }
    private static func pump(_ source: Int32, _ destination: Int32) {
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = recv(source, &buffer, buffer.count, 0)
            if count < 0 && errno == EINTR { continue }
            if count <= 0 { break }
            let completed = buffer.withUnsafeBytes { bytes -> Bool in
                var sent = 0
                while sent < count {
                    let result = send(destination, bytes.baseAddress!.advanced(by: sent), count - sent, 0)
                    if result < 0 && errno == EINTR { continue }
                    guard result > 0 else { return false }; sent += result
                }
                return true
            }
            if !completed { _ = shutdown(source, SHUT_RD); break }
        }
        _ = shutdown(destination, SHUT_WR)
    }
    private static func forwardDNS(_ listener: Int32, target: Int, slots: DispatchSemaphore) {
        while true {
            var request = [UInt8](repeating: 0, count: 16_384), peer = sockaddr_in(), length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &peer) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(listener, &request, request.count, 0, $0, &length) } }
            if count < 0 { if errno == EINTR { continue }; _exit(1) }
            guard count >= 12, peer.sin_family == sa_family_t(AF_INET), slots.wait(timeout: .now()) == .success else { continue }
            let payload = Data(request.prefix(count)), address = peer
            DispatchQueue.global(qos: .utility).async {
                defer { slots.signal() }
                let upstream = socket(AF_INET, SOCK_DGRAM, 0); guard upstream >= 0 else { return }; defer { Darwin.close(upstream) }
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                _ = setsockopt(upstream, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                guard connect(upstream, port: target) else { return }
                let written = payload.withUnsafeBytes { send(upstream, $0.baseAddress!, $0.count, 0) }; guard written == payload.count else { return }
                var response = [UInt8](repeating: 0, count: 16_384)
                let received = recv(upstream, &response, response.count, 0); guard received >= 12 else { return }
                var destination = address
                _ = withUnsafePointer(to: &destination) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(listener, &response, received, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            }
        }
    }
}
