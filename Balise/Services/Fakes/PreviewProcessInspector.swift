//
//  PreviewProcessInspector.swift
//  Balise
//

import Foundation

/// Reads from `FakeProcessWorld` instead of the machine.
nonisolated struct PreviewProcessInspector: ProcessInspecting {

    let world: FakeProcessWorld

    init(world: FakeProcessWorld) {
        self.world = world
    }

    func scan() async throws -> PortScan {
        try await world.scan()
    }
}
