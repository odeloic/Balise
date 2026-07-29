//
//  Stubs.swift
//  BaliseTests
//
//  Stand-in services a test can steer. Swift cannot patch a module at runtime,
//  so a fake handed to the initialiser is the only way to mock anything.
//

import Foundation
@testable import Balise

nonisolated struct StubError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

nonisolated struct StubProcessInspector: ProcessInspecting {

    var result: PortScan = .empty
    var failure: StubError?

    func scan() async throws -> PortScan {
        if let failure { throw failure }
        return result
    }
}

/// Records what it was asked to do, so a test can prove a call never happened.
actor RecordingProcessController: ProcessControlling {

    struct Call: Hashable, Sendable {
        let signal: TerminationSignal
        let pid: pid_t
    }

    private(set) var calls: [Call] = []
    private let failures: [ProcessControlError?]

    /// One entry per call, in order. `nil` means that call succeeds.
    /// Calls past the end of the list succeed.
    init(failures: [ProcessControlError?] = []) {
        self.failures = failures
    }

    func send(_ signal: TerminationSignal, to pid: pid_t) async throws {
        let index = calls.count
        calls.append(Call(signal: signal, pid: pid))
        if index < failures.count, let failure = failures[index] { throw failure }
    }
}

/// Holds the *first* scan open until the test lets it finish, so two
/// overlapping refreshes can be observed without leaning on timing.
///
/// Only the first one waits. A second scan returns straight away, so a store
/// that loses its re-entrancy guard fails the count check instead of hanging
/// on a gate nobody will ever open.
actor GatedProcessInspector: ProcessInspecting {

    private(set) var scanCount = 0
    private var inFlight: CheckedContinuation<Void, Never>?
    private var watchers: [CheckedContinuation<Void, Never>] = []

    func scan() async throws -> PortScan {
        scanCount += 1
        for watcher in watchers { watcher.resume() }
        watchers = []
        guard scanCount == 1 else { return .empty }
        await withCheckedContinuation { inFlight = $0 }
        return .empty
    }

    func waitUntilScanning() async {
        guard scanCount == 0 else { return }
        await withCheckedContinuation { watchers.append($0) }
    }

    func finish() {
        inFlight?.resume()
        inFlight = nil
    }
}
