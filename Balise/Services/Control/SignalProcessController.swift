//
//  SignalProcessController.swift
//  Balise
//
//  The real `kill`. The only code in the app that stops anything.
//

import Darwin
import Foundation

/// An actor for the same reason the inspector is one: the calls below must not
/// run on the thread that draws.
actor SignalProcessController: ProcessControlling {

    /// How long a process gets to honour `.terminate` before we report that it
    /// ignored us. Long enough for a database to flush, short enough that the
    /// menu does not feel stuck.
    private let grace: Duration

    init(grace: Duration = .milliseconds(1500)) {
        self.grace = grace
    }

    func send(_ signal: TerminationSignal, to pid: pid_t) async throws {
        // The short flavour, because the full one is refused for anything
        // outside your own account and a refusal should still name the process.
        let name = Libproc.shortInfo(of: pid)?.name ?? "That process"
        let startedBefore = Libproc.bsdInfo(of: pid)?.startedAt

        guard Libproc.isAlive(pid) else {
            throw ProcessControlError.noSuchProcess(name: name)
        }

        guard kill(pid, signal.signalNumber) == 0 else {
            switch errno {
            case ESRCH: throw ProcessControlError.noSuchProcess(name: name)
            default: throw ProcessControlError.notPermitted(name: name)
            }
        }

        // `.forceKill` cannot be refused, so there is nothing to wait for.
        guard signal == .terminate else { return }

        try await Task.sleep(for: grace)

        guard Libproc.isAlive(pid) else { return }

        // A process id is reused once the old one dies. Where the start time
        // is readable, matching it is what tells "still running" apart from
        // "gone, and something else took its number".
        if let startedBefore, Libproc.bsdInfo(of: pid)?.startedAt != startedBefore { return }

        throw ProcessControlError.ignored(name: name)
    }
}
