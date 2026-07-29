//
//  Orphan.swift
//  BaliseTests
//
//  Starts real processes to stop.
//

import Darwin
import Foundation
@testable import Balise

/// Starts a process that is deliberately **not** our child.
///
/// A dead child stays a zombie until its parent reaps it, and a zombie still
/// answers `kill(pid, 0)`. That would make a stopped process look alive and
/// turn these tests flaky. Handing the job to a shell that then exits leaves
/// the process parented to `launchd`, which reaps it at once. Balise stops
/// other people's processes in real use, so this is also the truer shape.
enum Orphan {

    struct Failure: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    static func start(_ command: String) throws -> pid_t {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "\(command) >/dev/null 2>&1 & echo $!"]

        let output = Pipe()
        shell.standardOutput = output
        try shell.run()

        let printed = output.fileHandleForReading.readDataToEndOfFile()
        shell.waitUntilExit()

        guard let text = String(data: printed, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = pid_t(text), pid > 0 else {
            throw Failure(reason: "could not read the process id of: \(command)")
        }
        return pid
    }

    /// Sleeps quietly and quits when asked.
    static func obedient() throws -> pid_t {
        try start("sleep 60")
    }

    /// Refuses `SIGTERM` outright, so the escalation path can be exercised.
    ///
    /// Waits for the shell to touch a marker file. Without that the signal can
    /// arrive before `trap` has run, and the process dies on the default
    /// disposition instead of refusing.
    static func stubborn() async throws -> pid_t {
        let marker = NSTemporaryDirectory() + "balise-stubborn-" + UUID().uuidString
        let pid = try start(
            #"/bin/sh -c 'trap "" TERM; touch \#(marker); while :; do sleep 1; done'"#
        )

        guard await waitForFile(marker) else {
            kill(pid)
            throw Failure(reason: "the stubborn process never installed its trap")
        }
        try? FileManager.default.removeItem(atPath: marker)
        return pid
    }

    private static func waitForFile(_ path: String, within limit: Duration = .seconds(10)) async -> Bool {
        let step = Duration.milliseconds(20)
        var waited = Duration.zero

        while waited < limit {
            if FileManager.default.fileExists(atPath: path) { return true }
            try? await Task.sleep(for: step)
            waited += step
        }
        return FileManager.default.fileExists(atPath: path)
    }

    static func kill(_ pid: pid_t) {
        _ = Darwin.kill(pid, SIGKILL)
    }

    /// Waits for a process to leave the table. Returns false if it outstays.
    ///
    /// Asks the same question the controller asks. `bsdInfo` stops answering
    /// for a process that has died but not yet been reaped, while `kill(pid, 0)`
    /// still says yes — so a looser test here reports "gone" a beat early and
    /// the test that follows it fails now and then.
    static func waitUntilGone(_ pid: pid_t, within limit: Duration = .seconds(5)) async -> Bool {
        let step = Duration.milliseconds(20)
        var waited = Duration.zero

        while waited < limit {
            if !Libproc.isAlive(pid) { return true }
            try? await Task.sleep(for: step)
            waited += step
        }
        return !Libproc.isAlive(pid)
    }
}
