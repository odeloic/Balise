//
//  BaliseApp.swift
//  Balise
//
//  Created by Loic Ishimwe on 23.07.26.
//

import SwiftUI

@main
struct BaliseApp: App {
    var body: some Scene {
        MenuBarExtra("Balise", systemImage: "globe") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
