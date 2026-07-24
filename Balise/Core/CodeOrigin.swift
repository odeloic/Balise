//
//  CodeOrigin.swift
//  Balise
//
//  Where a binary came from, according to its code signature.
//

import Foundation

/// Who signed the binary behind a process.
///
/// macOS signs almost everything. The signature says who built it, and that is
/// the closest thing to a trustworthy answer for "what is this thing?".
/// Reading it is the job of a service in `Services/Origin/`.
nonisolated enum CodeOrigin: Hashable, Sendable {

    /// Shipped with macOS, signed by Apple itself.
    case apple

    /// Downloaded from the Mac App Store.
    case appStore(bundleID: String?)

    /// Signed by a named developer with an Apple account.
    /// This covers most apps installed outside the App Store.
    case developerID(teamID: String, teamName: String?)

    /// Signed, but with a throwaway identity that proves nothing about who made it.
    /// Normal for locally built binaries and many Homebrew tools.
    case adHoc

    /// No signature at all.
    case unsigned

    /// The signature could not be read.
    ///
    /// Usually means the process belongs to another user, not that anything
    /// is wrong. Keep the reason so the interface can say something useful.
    case unreadable(reason: String)

    /// Short text for a badge in the list.
    var label: String {
        switch self {
        case .apple: "Apple"
        case .appStore: "App Store"
        case .developerID(_, let name): name ?? "Identified Developer"
        case .adHoc: "Ad Hoc"
        case .unsigned: "Unsigned"
        case .unreadable: "Unknown"
        }
    }

    /// Rough trust ranking, for sorting or colouring rows.
    ///
    /// This is a hint for the interface, not a security decision. An unsigned
    /// binary is not automatically bad — most things you build yourself are unsigned.
    var trust: TrustLevel {
        switch self {
        case .apple, .appStore: .system
        case .developerID: .identified
        case .adHoc, .unsigned: .anonymous
        case .unreadable: .unknown
        }
    }
}

nonisolated enum TrustLevel: Int, Hashable, Sendable, Comparable {
    case unknown = 0
    case anonymous = 1
    case identified = 2
    case system = 3

    static func < (lhs: TrustLevel, rhs: TrustLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
