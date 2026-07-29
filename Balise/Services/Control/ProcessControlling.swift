//
//  ProcessControlling.swift
//  Balise
//
//  Stopping a process. The only place in the app that can.
//

import Foundation

/// Sends a stop signal to a process.
nonisolated protocol ProcessControlling: Sendable {

    /// Asks the process to stop.
    ///
    /// Returning without throwing means the signal was delivered, not that the
    /// process is gone. A process is free to ignore `.terminate`; the caller
    /// should re-scan and offer `.forceKill` if it is still there.
    func send(_ signal: TerminationSignal, to pid: pid_t) async throws
}

nonisolated enum ProcessControlError: LocalizedError, Hashable, Sendable {

    /// The process belongs to `root` or another user.
    case notPermitted(name: String)

    /// It already exited between the scan and the click.
    case noSuchProcess(name: String)

    /// The signal was delivered and the process carried on regardless.
    case ignored(name: String)

    var errorDescription: String? {
        switch self {
        case .notPermitted(let name):
            "\(name) belongs to another user. Balise cannot stop it."
        case .noSuchProcess(let name):
            "\(name) had already stopped."
        case .ignored(let name):
            "\(name) ignored the request to quit."
        }
    }
}
