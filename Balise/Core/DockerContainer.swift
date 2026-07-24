//
//  DockerContainer.swift
//  Balise
//
//  A Docker container and its live resource use.
//

import Foundation

/// One container, running or not.
nonisolated struct DockerContainer: Identifiable, Hashable, Sendable {

    /// Full 64 character container id. Use `shortID` for display.
    let id: String

    /// Container name without Docker's leading slash, e.g. `postgres-dev`.
    let name: String

    /// Image it was built from, e.g. `postgres:16`.
    let image: String

    let state: State

    /// Docker's own wording, e.g. `Up 3 hours` or `Exited (0) 2 days ago`.
    /// Easier to show this than to rebuild the phrasing ourselves.
    let status: String

    /// Ports mapped out to the Mac. Empty when nothing is published.
    let publishedPorts: [PublishedPort]

    let createdAt: Date?

    /// The first 12 characters, which is what the `docker` command shows.
    var shortID: String { String(id.prefix(12)) }

    nonisolated enum State: String, Hashable, Sendable, CaseIterable {
        case created
        case running
        case paused
        case restarting
        case exited
        case dead
        case removing

        /// True when the container is doing work and can be stopped.
        var isActive: Bool {
            switch self {
            case .running, .restarting, .paused: true
            case .created, .exited, .dead, .removing: false
            }
        }

        var label: String { rawValue.capitalized }
    }
}

/// A container port opened up on the Mac, so `localhost:hostPort` reaches it.
nonisolated struct PublishedPort: Identifiable, Hashable, Sendable {

    /// The port on your Mac.
    let hostPort: UInt16

    /// The port inside the container.
    let containerPort: UInt16

    let transport: TransportProtocol

    var id: String { "\(hostPort)-\(containerPort)-\(transport.rawValue)" }
}

/// What one container is using right now.
///
/// Kept apart from `DockerContainer` on purpose: the list of containers changes
/// rarely, while these numbers change every second. Splitting them means
/// refreshing the numbers does not redraw the whole list.
nonisolated struct ContainerResourceUsage: Hashable, Sendable {

    let containerID: String

    /// Share of the host's processing power, `0.0` to `1.0`.
    /// Can go above `1.0` when a container uses more than one core.
    let cpuShare: Double

    /// Memory held right now, in bytes.
    let memoryUsedBytes: UInt64

    /// The container's memory ceiling, in bytes. `nil` when unlimited.
    let memoryLimitBytes: UInt64?

    /// Memory used as a share of the limit, `0.0` to `1.0`.
    /// `nil` when there is no limit to measure against.
    var memoryShare: Double? {
        guard let limit = memoryLimitBytes, limit > 0 else { return nil }
        return Double(memoryUsedBytes) / Double(limit)
    }
}
