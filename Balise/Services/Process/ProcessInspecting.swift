//
//  ProcessInspecting.swift
//  Balise
//
//  Reading what is listening. Read-only, always.
//

import Foundation

/// Finds every listening port and the process behind it.
///
/// Nothing here changes the state of the machine. Stopping a process lives
/// behind `ProcessControlling` in `Services/Control/`, so a refresh loop can
/// never reach it by accident.
nonisolated protocol ProcessInspecting: Sendable {

    /// One full sweep. Safe to call repeatedly.
    func scan() async throws -> PortScan
}
