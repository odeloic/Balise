//
//  PreviewProcessController.swift
//  Balise
//

import Foundation

/// Removes rows from `FakeProcessWorld`. Sends no real signal to anything.
nonisolated struct PreviewProcessController: ProcessControlling {

    let world: FakeProcessWorld

    init(world: FakeProcessWorld) {
        self.world = world
    }

    func send(_ signal: TerminationSignal, to pid: pid_t) async throws {
        try await world.send(signal, to: pid)
    }
}
