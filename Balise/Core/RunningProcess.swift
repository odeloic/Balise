//
//  RunningProcess.swift
//  Balise
//
//  A single process running on this Mac.
//

import Foundation

/// One process, as Balise sees it.
///
/// This is pure data. Nothing here talks to the system — filling it in is the
/// job of a service in `Services/Process/`.
nonisolated struct RunningProcess: Identifiable, Hashable, Sendable {

    /// The process id. Unique while the process lives, reused after it dies.
    let pid: pid_t

    /// The process that launched this one. `1` means `launchd`, the root of the tree.
    let parentPID: pid_t

    /// Short name, e.g. `node`. This is what Activity Monitor shows.
    let name: String

    /// Full path to the binary, e.g. `/usr/local/bin/node`.
    ///
    /// `nil` when macOS refuses to tell us — normally a process owned by
    /// another user or by `root`.
    let executablePath: String?

    /// Who this process belongs to.
    let owner: ProcessOwner

    /// When the process started. `nil` when unreadable.
    let startedAt: Date?

    var id: pid_t { pid }
}

/// The user account a process runs as.
nonisolated struct ProcessOwner: Hashable, Sendable {

    /// Numeric user id. `0` is `root`.
    let userID: uid_t

    /// Account name, e.g. `loicishimwe`. `nil` if it can't be looked up.
    let username: String?

    /// True when the process belongs to whoever is running Balise.
    ///
    /// Worth checking before showing details or offering a Stop button:
    /// macOS only lets us inspect and signal our own processes.
    var isCurrentUser: Bool { userID == getuid() }

    /// True for `root`-owned system processes.
    var isRoot: Bool { userID == 0 }
}
