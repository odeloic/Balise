//
//  SoftwareSource.swift
//  Balise
//
//  Where a binary came from, judged by its path.
//

import Foundation

/// A rough answer to "what installed this?", read straight off the path.
///
/// This is not a security check — a path can be anything, and nothing here is
/// verified. It exists because it is free and it is what you actually want to
/// know day to day: is this mine, is it Homebrew's, or is it the system's.
/// The verified answer lives in `CodeOrigin` and costs a signature read.
nonisolated enum SoftwareSource: Hashable, Sendable {

    case homebrew
    case application(name: String)
    case system

    /// Somewhere under the current user's home folder.
    case user

    case unknown

    init(executablePath: String?) {
        guard let path = executablePath, !path.isEmpty else {
            self = .unknown
            return
        }

        if path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/Cellar/") {
            self = .homebrew
        } else if let bundle = path.range(of: ".app/Contents/MacOS/") {
            let appPath = String(path[..<bundle.lowerBound])
            self = .application(name: (appPath as NSString).lastPathComponent)
        } else if path.hasPrefix("/System/") || path.hasPrefix("/usr/bin/")
                    || path.hasPrefix("/usr/sbin/") || path.hasPrefix("/usr/libexec/")
                    || path.hasPrefix("/sbin/") {
            self = .system
        } else if path.hasPrefix(NSHomeDirectory() + "/") {
            self = .user
        } else {
            self = .unknown
        }
    }

    var label: String {
        switch self {
        case .homebrew: "Homebrew"
        case .application(let name): name
        case .system: "macOS"
        case .user: "Yours"
        case .unknown: "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .homebrew: "shippingbox"
        case .application: "app"
        case .system: "apple.logo"
        case .user: "person"
        case .unknown: "questionmark"
        }
    }
}
