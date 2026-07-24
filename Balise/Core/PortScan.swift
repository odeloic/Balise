//
//  PortScan.swift
//  Balise
//
//  One complete look at what is listening on this Mac.
//

import Foundation

/// The result of a single sweep.
///
/// Ports and processes are kept apart rather than merged into one flat list
/// because one process often holds several ports — an ssh tunnel can hold
/// three — and repeating the whole process for each of them is waste.
/// Flattening for display is the store's job.
nonisolated struct PortScan: Hashable, Sendable {

    let ports: [ListeningPort]

    /// Every process that holds at least one port in `ports`, keyed by id.
    let processes: [pid_t: RunningProcess]

    let scannedAt: Date

    /// How many processes macOS refused to open. Normally a few hundred, all
    /// owned by `root` or another user. Worth showing so an empty-looking
    /// result never reads as "nothing is running".
    let unreadableProcessCount: Int

    func process(for port: ListeningPort) -> RunningProcess? {
        processes[port.pid]
    }

    static let empty = PortScan(
        ports: [],
        processes: [:],
        scannedAt: .distantPast,
        unreadableProcessCount: 0
    )
}
