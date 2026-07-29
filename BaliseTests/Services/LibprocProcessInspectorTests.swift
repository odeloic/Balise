//
//  LibprocProcessInspectorTests.swift
//  BaliseTests
//
//  Real sweeps of the real machine.
//

import Darwin
import Foundation
import Testing
@testable import Balise

@Suite("LibprocProcessInspector")
struct LibprocProcessInspectorTests {

    @Test("a scan finds a socket this very process is listening on")
    func findsOurOwnTCPSocket() async throws {
        let socket = try TestSocket(transport: .tcp, family: .ipv4)
        let scan = try await LibprocProcessInspector().scan()

        let found = try #require(scan.ports.first {
            $0.number == socket.port && $0.pid == getpid()
        })
        #expect(found.transport == .tcp)
        #expect(found.addressFamily == .ipv4)

        withExtendedLifetime(socket) {}
    }

    @Test("an IPv6 socket is reported as IPv6")
    func findsIPv6() async throws {
        let socket = try TestSocket(transport: .tcp, family: .ipv6)
        let scan = try await LibprocProcessInspector().scan()

        let found = try #require(scan.ports.first {
            $0.number == socket.port && $0.pid == getpid()
        })
        #expect(found.addressFamily == .ipv6)

        withExtendedLifetime(socket) {}
    }

    /// UDP has no listen state, so a bound port with no peer is the test.
    @Test("a bound UDP port is reported as UDP")
    func findsUDP() async throws {
        let socket = try TestSocket(transport: .udp, family: .ipv4)
        let scan = try await LibprocProcessInspector().scan()

        let found = try #require(scan.ports.first {
            $0.number == socket.port && $0.pid == getpid()
        })
        #expect(found.transport == .udp)

        withExtendedLifetime(socket) {}
    }

    @Test("a closed socket is gone by the next scan")
    func closedSocketDisappears() async throws {
        let inspector = LibprocProcessInspector()

        var socket: TestSocket? = try TestSocket(transport: .tcp, family: .ipv4)
        let port = try #require(socket?.port)
        let before = try await inspector.scan()
        #expect(before.ports.contains { $0.number == port && $0.pid == getpid() })

        socket = nil
        let after = try await inspector.scan()
        #expect(!after.ports.contains { $0.number == port && $0.pid == getpid() })
    }

    @Test("the process behind our socket is described")
    func describesTheHoldingProcess() async throws {
        let socket = try TestSocket(transport: .tcp, family: .ipv4)
        let scan = try await LibprocProcessInspector().scan()

        let port = try #require(scan.ports.first { $0.number == socket.port && $0.pid == getpid() })
        let process = try #require(scan.process(for: port))

        #expect(process.pid == getpid())
        #expect(!process.name.isEmpty)
        #expect(process.owner.isCurrentUser)
        #expect(process.executablePath?.hasSuffix("/Balise") == true)
        #expect(process.arguments?.isEmpty == false)
        #expect(process.startedAt != nil)

        withExtendedLifetime(socket) {}
    }

    @Test("every port reported is a real one")
    func portsAreSane() async throws {
        let scan = try await LibprocProcessInspector().scan()

        #expect(scan.ports.allSatisfy { $0.number > 0 })
        #expect(scan.ports.allSatisfy { $0.pid > 0 })
        #expect(scan.scannedAt.timeIntervalSinceNow > -10)
    }

    /// One socket can sit behind several file descriptors. Each of those is a
    /// row unless the scan collapses them.
    @Test("a duplicated file descriptor does not become a second row")
    func duplicateDescriptors() async throws {
        let socket = try TestSocket(transport: .tcp, family: .ipv4)
        let copy = dup(socket.handle)
        defer { close(copy) }
        try #require(copy >= 0)

        let scan = try await LibprocProcessInspector().scan()
        let matches = scan.ports.filter { $0.number == socket.port && $0.pid == getpid() }

        #expect(matches.count == 1)

        withExtendedLifetime(socket) {}
    }

    /// Most of the machine belongs to `root`, and macOS will not open those.
    /// Reporting the count is what stops a short list reading as "nothing runs".
    @Test("processes macOS refuses to open are counted, not dropped silently")
    func countsUnreadableProcesses() async throws {
        let scan = try await LibprocProcessInspector().scan()
        #expect(scan.unreadableProcessCount > 0)
    }
}
