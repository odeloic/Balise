//
//  BaliseApp.swift
//  Balise
//
//  Created by Loic Ishimwe on 23.07.26.
//

import SwiftUI

@main
struct BaliseApp: App {

    /// Both services share one fake machine, so stopping a process in the list
    /// really does remove it. Swapping in `LibprocProcessInspector` later
    /// changes these two lines and nothing else.
    private static let world = FakeProcessWorld()

    @State private var processes = ProcessListStore(
        inspector: PreviewProcessInspector(world: BaliseApp.world),
        controller: PreviewProcessController(world: BaliseApp.world)
    )

    var body: some Scene {
        MenuBarExtra("Balise", systemImage: "dot.radiowaves.left.and.right") {
            ProcessListView(store: processes)
        }
        .menuBarExtraStyle(.window)
    }
}
