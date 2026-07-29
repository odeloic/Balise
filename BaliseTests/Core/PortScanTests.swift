//
//  PortScanTests.swift
//  BaliseTests
//

import Foundation
import Testing
@testable import Balise

@Suite("PortScan and ProcessRow")
struct PortScanTests {

    @Test("rows run lowest port first, IPv4 before IPv6")
    func sortOrder() {
        let scan = Fixture.scan(
            ports: [
                Fixture.port(5432, pid: 10, family: .ipv6),
                Fixture.port(8080, pid: 11),
                Fixture.port(5432, pid: 10, family: .ipv4),
                Fixture.port(631, pid: 12),
            ],
            processes: [Fixture.process(pid: 10), Fixture.process(pid: 11), Fixture.process(pid: 12)]
        )

        let identity = scan.rows.map { "\($0.port.number)/\($0.port.addressFamily.rawValue)" }
        #expect(identity == ["631/ipv4", "5432/ipv4", "5432/ipv6", "8080/ipv4"])
    }

    /// The same port over both families is two rows on purpose. Merging them
    /// would hide something the machine actually reports.
    @Test("one port over two families stays two rows")
    func familiesAreNotMerged() {
        let scan = Fixture.scan(
            ports: [
                Fixture.port(5432, pid: 10, family: .ipv4),
                Fixture.port(5432, pid: 10, family: .ipv6),
            ],
            processes: [Fixture.process(pid: 10, name: "postgres")]
        )

        #expect(scan.rows.count == 2)
        #expect(Set(scan.rows.map(\.id)).count == 2)
    }

    @Test("a port with no known process still gets a row")
    func unknownProcess() throws {
        let scan = Fixture.scan(ports: [Fixture.port(5432, pid: 404)])
        let row = try #require(scan.rows.first)

        #expect(row.process == nil)
        #expect(row.name == "Unknown process")
        #expect(row.source == .unknown)
        #expect(!row.canStop)
        #expect(row.ownerLabel == "unknown")
    }

    @Test("a process is found by the port it holds")
    func processLookup() {
        let port = Fixture.port(5432, pid: 10)
        let scan = Fixture.scan(ports: [port], processes: [Fixture.process(pid: 10, name: "postgres")])

        #expect(scan.process(for: port)?.name == "postgres")
        #expect(scan.process(for: Fixture.port(9999, pid: 999)) == nil)
    }

    @Test("the empty scan has nothing in it")
    func emptyScan() {
        #expect(PortScan.empty.rows.isEmpty)
        #expect(PortScan.empty.unreadableProcessCount == 0)
        #expect(PortScan.empty.scannedAt == .distantPast)
    }

    @Test("only your own processes can be stopped")
    func stoppability() {
        let mine = ProcessRow(port: Fixture.port(5432, pid: 10),
                              process: Fixture.process(pid: 10, owner: Fixture.currentUser))
        let theirs = ProcessRow(port: Fixture.port(631, pid: 11),
                                process: Fixture.process(pid: 11, owner: Fixture.root))

        #expect(mine.canStop)
        #expect(!theirs.canStop)
    }

    @Test("the owner label says who, or at least which account number")
    func ownerLabels() {
        let mine = ProcessRow(port: Fixture.port(1, pid: 10),
                              process: Fixture.process(pid: 10, owner: Fixture.currentUser))
        let root = ProcessRow(port: Fixture.port(2, pid: 11),
                              process: Fixture.process(pid: 11, owner: Fixture.root))
        let nameless = ProcessRow(port: Fixture.port(3, pid: 12),
                                  process: Fixture.process(pid: 12, owner: Fixture.stranger))

        #expect(mine.ownerLabel == "you")
        #expect(root.ownerLabel == "root")
        #expect(nameless.ownerLabel == "uid 99")
    }

    @Test("a row takes its source from the process path")
    func rowSource() {
        let row = ProcessRow(
            port: Fixture.port(5432, pid: 10),
            process: Fixture.process(pid: 10, executablePath: "/opt/homebrew/bin/postgres")
        )
        #expect(row.source == .homebrew)
    }
}
