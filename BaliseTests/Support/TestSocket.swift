//
//  TestSocket.swift
//  BaliseTests
//
//  A real listening socket owned by the test process, so a real scan has
//  something it must find.
//

import Darwin
import Foundation
@testable import Balise

final class TestSocket {

    let handle: Int32
    let port: UInt16
    let transport: TransportProtocol
    let family: AddressFamily

    struct Failure: LocalizedError {
        let call: String
        let code: Int32
        var errorDescription: String? { "\(call) failed with errno \(code)" }
    }

    init(transport: TransportProtocol, family: AddressFamily) throws {
        self.transport = transport
        self.family = family

        let domain = family == .ipv4 ? AF_INET : AF_INET6
        let kind = transport == .tcp ? SOCK_STREAM : SOCK_DGRAM

        handle = socket(domain, kind, 0)
        guard handle >= 0 else { throw Failure(call: "socket", code: errno) }

        var reuse: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        do {
            try Self.bindToAnyPort(handle, family: family)
            if transport == .tcp, listen(handle, 1) != 0 {
                throw Failure(call: "listen", code: errno)
            }
            port = try Self.boundPort(handle, family: family)
        } catch {
            close(handle)
            throw error
        }
    }

    deinit { close(handle) }

    private static func bindToAnyPort(_ handle: Int32, family: AddressFamily) throws {
        let bound: Int32
        switch family {
        case .ipv4:
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = 0
            address.sin_addr = in_addr(s_addr: INADDR_ANY)
            bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        case .ipv6:
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = 0
            address.sin6_addr = in6addr_any
            bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
        guard bound == 0 else { throw Failure(call: "bind", code: errno) }
    }

    private static func boundPort(_ handle: Int32, family: AddressFamily) throws -> UInt16 {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)

        let read = withUnsafeMutablePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(handle, $0, &length)
            }
        }
        guard read == 0 else { throw Failure(call: "getsockname", code: errno) }

        let networkOrder: UInt16 = withUnsafeBytes(of: storage) { raw in
            switch family {
            case .ipv4: raw.load(as: sockaddr_in.self).sin_port
            case .ipv6: raw.load(as: sockaddr_in6.self).sin6_port
            }
        }
        return UInt16(bigEndian: networkOrder)
    }
}
