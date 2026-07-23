//
//  ContentView.swift
//  Balise
//
//  Created by Loic Ishimwe on 23.07.26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")

            Divider()

            Button("Quit Balise") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 220)
    }
}

#Preview {
    ContentView()
}
