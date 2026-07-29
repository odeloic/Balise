//
//  LibprocProcessInspector.swift
//  Balise
//
//  The real sweep: every process, every listening socket.
//

import Darwin
import Foundation

/// An actor, not a struct, and that is the whole point.
///
/// `SWIFT_APPROACHABLE_CONCURRENCY` makes a `nonisolated async` function run on
/// whoever called it. Called from a store, that is the main thread, and the
/// sweep below would draw-block the menu. An actor has its own executor, so the
/// work lands off the main thread no matter who asks.
actor LibprocProcessInspector: ProcessInspecting {

    func scan() async throws -> PortScan {
        var ports: [ListeningPort] = []
        var seen: Set<String> = []
        var holders: [pid_t] = []
        var unreadable = 0

        for pid in Libproc.allPIDs() {
            guard let sockets = Libproc.listeningSockets(of: pid) else {
                unreadable += 1
                continue
            }
            guard !sockets.isEmpty else { continue }

            var holdsAPort = false
            for socket in sockets {
                let port = ListeningPort(
                    number: socket.port,
                    transport: socket.transport,
                    addressFamily: socket.family,
                    pid: pid
                )
                // Two file descriptors can point at one socket, after a fork
                // or a dup. That is one port, not two.
                guard seen.insert(port.id).inserted else { continue }
                ports.append(port)
                holdsAPort = true
            }
            if holdsAPort { holders.append(pid) }
        }

        var processes: [pid_t: RunningProcess] = [:]
        processes.reserveCapacity(holders.count)
        for pid in holders {
            if let process = describe(pid) { processes[pid] = process }
        }

        return PortScan(
            ports: ports,
            processes: processes,
            scannedAt: Date(),
            unreadableProcessCount: unreadable
        )
    }

    /// The command line is read here rather than on demand because `holders`
    /// is only the handful of processes that hold a port, not all 700-odd.
    private func describe(_ pid: pid_t) -> RunningProcess? {
        guard let info = Libproc.bsdInfo(of: pid) else { return nil }

        return RunningProcess(
            pid: pid,
            parentPID: info.parentPID,
            name: info.name,
            executablePath: Libproc.executablePath(of: pid),
            owner: ProcessOwner(userID: info.userID, username: Libproc.username(for: info.userID)),
            startedAt: info.startedAt,
            workingDirectory: Libproc.workingDirectory(of: pid),
            arguments: Libproc.arguments(of: pid)
        )
    }
}
