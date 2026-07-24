//
//  TerminationSignal.swift
//  Balise
//
//  How to ask a process to stop.
//

import Foundation

/// The two ways Balise can stop a process.
///
/// Kept as a type rather than a raw number so that "stop this" can never be
/// confused with some other signal by accident.
nonisolated enum TerminationSignal: Hashable, Sendable, CaseIterable {

    /// Ask politely. The process gets to save its work and shut down cleanly.
    /// It is also allowed to ignore this. Always try this first.
    case terminate

    /// Pull the plug. The kernel stops the process immediately and it cannot
    /// refuse. Nothing gets saved. Only after `terminate` has failed.
    case forceKill

    /// The POSIX signal number to hand to `kill`.
    var signalNumber: Int32 {
        switch self {
        case .terminate: SIGTERM
        case .forceKill: SIGKILL
        }
    }

    var label: String {
        switch self {
        case .terminate: "Quit"
        case .forceKill: "Force Quit"
        }
    }

    /// True when the interface should ask "are you sure?" first.
    var needsConfirmation: Bool {
        switch self {
        case .terminate: false
        case .forceKill: true
        }
    }
}
