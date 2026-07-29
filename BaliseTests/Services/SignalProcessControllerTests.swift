//
//  SignalProcessControllerTests.swift
//  BaliseTests
//
//  Stopping real processes. Everything started here is cleaned up.
//

import Darwin
import Foundation
import Testing
@testable import Balise

@Suite("SignalProcessController")
struct SignalProcessControllerTests {

    private func controller() -> SignalProcessController {
        SignalProcessController(grace: .milliseconds(400))
    }

    @Test("a polite quit stops a process that is willing")
    func terminateStopsIt() async throws {
        let pid = try Orphan.obedient()
        defer { Orphan.kill(pid) }

        try await controller().send(.terminate, to: pid)

        #expect(await Orphan.waitUntilGone(pid))
    }

    /// The process is allowed to say no. That is reported as `.ignored`, which
    /// is what turns the button into a force quit prompt.
    @Test("a process that refuses to quit is reported, not forced")
    func terminateReportsRefusal() async throws {
        let pid = try await Orphan.stubborn()
        defer { Orphan.kill(pid) }

        // Read the name off the process rather than spelling it out: `/bin/sh`
        // on macOS reports itself as `bash`, and that could change again.
        let name = try #require(Libproc.shortInfo(of: pid)?.name)

        await #expect(throws: ProcessControlError.ignored(name: name)) {
            try await controller().send(.terminate, to: pid)
        }
        #expect(Libproc.isAlive(pid))
    }

    @Test("force quit stops a process that refused to quit")
    func forceKillWins() async throws {
        let pid = try await Orphan.stubborn()
        defer { Orphan.kill(pid) }

        await #expect(throws: ProcessControlError.self) {
            try await controller().send(.terminate, to: pid)
        }

        try await controller().send(.forceKill, to: pid)
        #expect(await Orphan.waitUntilGone(pid))
    }

    @Test("a process that already stopped is reported as gone")
    func alreadyGone() async throws {
        let pid = try Orphan.obedient()
        Orphan.kill(pid)
        try #require(await Orphan.waitUntilGone(pid))

        await #expect(throws: ProcessControlError.noSuchProcess(name: "That process")) {
            try await controller().send(.terminate, to: pid)
        }
    }

    /// `launchd` is `root`-owned and protected, so this is a refusal and
    /// nothing else. Skipped when the tests run as `root`, where it would
    /// stop being a no-op.
    @Test("another user's process is refused", .enabled(if: getuid() != 0))
    func refusesAnotherUsersProcess() async throws {
        await #expect(throws: ProcessControlError.notPermitted(name: "launchd")) {
            try await controller().send(.terminate, to: 1)
        }
    }

    /// Force quit cannot be argued with, so there is no grace period to sit
    /// through. A slow answer here means the wait is being applied to both.
    @Test("force quit does not wait around", .timeLimit(.minutes(1)))
    func forceKillDoesNotWait() async throws {
        let controller = SignalProcessController(grace: .seconds(30))
        let pid = try Orphan.obedient()
        defer { Orphan.kill(pid) }

        let start = ContinuousClock.now
        try await controller.send(.forceKill, to: pid)

        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
