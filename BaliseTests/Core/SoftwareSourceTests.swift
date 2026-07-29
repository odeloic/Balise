//
//  SoftwareSourceTests.swift
//  BaliseTests
//

import Foundation
import Testing
@testable import Balise

@Suite("SoftwareSource")
struct SoftwareSourceTests {

    @Test("reads the source off the path", arguments: [
        ("/opt/homebrew/bin/node", SoftwareSource.homebrew),
        ("/opt/homebrew/opt/postgresql@15/bin/postgres", .homebrew),
        ("/usr/local/Cellar/redis/7.2/bin/redis-server", .homebrew),
        ("/Applications/Spotify.app/Contents/MacOS/Spotify", .application(name: "Spotify")),
        ("/usr/bin/ssh", .system),
        ("/usr/sbin/cupsd", .system),
        ("/usr/libexec/rapportd", .system),
        ("/sbin/launchd", .system),
        ("/opt/local/bin/thing", .unknown),
        ("", .unknown),
    ])
    func sourceForPath(path: String, expected: SoftwareSource) {
        #expect(SoftwareSource(executablePath: path) == expected)
    }

    @Test("no path means no answer")
    func missingPath() {
        #expect(SoftwareSource(executablePath: nil) == .unknown)
    }

    @Test("anything under home belongs to you")
    func homeFolder() {
        let path = NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb"
        #expect(SoftwareSource(executablePath: path) == .user)
    }

    /// The bundle check runs before the `/System/` check, so a system app is
    /// named rather than lumped in with macOS. Deliberate — "ControlCenter"
    /// tells you more than "macOS" does.
    @Test("a system app is named, not called macOS")
    func systemAppKeepsItsName() {
        let path = "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"
        #expect(SoftwareSource(executablePath: path) == .application(name: "ControlCenter"))
    }

    @Test("every source has a label and a symbol")
    func presentation() {
        #expect(SoftwareSource.homebrew.label == "Homebrew")
        #expect(SoftwareSource.application(name: "Spotify").label == "Spotify")
        #expect(SoftwareSource.system.label == "macOS")
        #expect(SoftwareSource.user.label == "Yours")
        #expect(SoftwareSource.unknown.label == "Unknown")
        #expect(SoftwareSource.homebrew.symbolName == "shippingbox")
    }
}
