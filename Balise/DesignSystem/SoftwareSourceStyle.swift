//
//  SoftwareSourceStyle.swift
//  Balise
//
//  How a software source looks.
//

import SwiftUI

extension SoftwareSource {

    /// One colour per source, so the left edge of the list can be read without
    /// reading any words.
    var tint: Color {
        switch self {
        case .homebrew: .orange
        case .application: .blue
        case .system: .gray
        case .user: .green
        case .unknown: Color(white: 0.55)
        }
    }
}
