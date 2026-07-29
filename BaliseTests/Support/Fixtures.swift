//
//  Fixtures.swift
//  BaliseTests
//
//  Builders for the Core types, so a test names only what it cares about.
//

import Foundation
@testable import Balise

enum Fixture {

    static let currentUser = ProcessOwner(userID: getuid(), username: NSUserName())
    static let root = ProcessOwner(userID: 0, username: "root")
    static let stranger = ProcessOwner(userID: 99, username: nil)

    static func process(
        pid: pid_t,
        parentPID: pid_t = 1,
        name: String = "node",
        executablePath: String? = "/opt/homebrew/bin/node",
        owner: ProcessOwner = currentUser,
        startedAt: Date? = nil,
        workingDirectory: String? = nil,
        arguments: [String]? = nil
    ) -> RunningProcess {
        RunningProcess(
            pid: pid,
            parentPID: parentPID,
            name: name,
            executablePath: executablePath,
            owner: owner,
            startedAt: startedAt,
            workingDirectory: workingDirectory,
            arguments: arguments
        )
    }

    static func port(
        _ number: UInt16,
        pid: pid_t,
        transport: TransportProtocol = .tcp,
        family: AddressFamily = .ipv4
    ) -> ListeningPort {
        ListeningPort(number: number, transport: transport, addressFamily: family, pid: pid)
    }

    static func scan(
        ports: [ListeningPort],
        processes: [RunningProcess] = [],
        unreadableProcessCount: Int = 0
    ) -> PortScan {
        PortScan(
            ports: ports,
            processes: Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) }),
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
            unreadableProcessCount: unreadableProcessCount
        )
    }
}
