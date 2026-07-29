//
//  BaliseApp.swift
//  Balise
//
//  Created by Loic Ishimwe on 23.07.26.
//

import SwiftUI

@main
struct BaliseApp: App {

    @State private var processes = ProcessListStore(
        inspector: LibprocProcessInspector(),
        controller: SignalProcessController()
    )

    var body: some Scene {
        MenuBarExtra("Balise", systemImage: "dot.radiowaves.left.and.right") {
            ProcessListView(store: processes)
        }
        .menuBarExtraStyle(.window)
    }
}
