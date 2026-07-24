//
//  ProcessRow.swift
//  Balise
//
//  One line in the list: a port and whatever we know about its owner.
//

import Foundation

/// A port paired with its process, ready to draw.
///
/// The process is optional because macOS can hand back a listening socket
/// while refusing to say anything about the process holding it. That row is
/// still worth showing — "something has 5432" beats leaving a gap.
nonisolated struct ProcessRow: Identifiable, Hashable, Sendable {

    let port: ListeningPort
    let process: RunningProcess?

    var id: String { port.id }

    var name: String { process?.name ?? "Unknown process" }

    var pid: pid_t { port.pid }

    /// macOS only lets us signal our own processes, so anything else has no
    /// Stop button rather than a button that always fails.
    var canStop: Bool { process?.owner.isCurrentUser == true }

    var ownerLabel: String {
        guard let owner = process?.owner else { return "unknown" }
        if owner.isCurrentUser { return "you" }
        return owner.username ?? "uid \(owner.userID)"
    }

    var source: SoftwareSource { process?.source ?? .unknown }
}

extension PortScan {

    /// Flattens a scan into display order: lowest port first, IPv4 before IPv6.
    var rows: [ProcessRow] {
        ports
            .map { ProcessRow(port: $0, process: process(for: $0)) }
            .sorted {
                if $0.port.number != $1.port.number {
                    return $0.port.number < $1.port.number
                }
                return $0.port.addressFamily.rawValue < $1.port.addressFamily.rawValue
            }
    }
}
