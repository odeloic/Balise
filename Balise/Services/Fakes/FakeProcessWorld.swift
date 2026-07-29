//
//  FakeProcessWorld.swift
//  Balise
//
//  A pretend Mac. Nothing here touches the real machine.
//

import Foundation

/// Stands in for the machine while the interface is being built.
///
/// It holds state on purpose. Stopping a process has to actually remove a row,
/// otherwise there is no way to see the confirm, the empty state, or a failure
/// before the real code exists. The numbers below are a real scan of a
/// developer Mac, awkward cases included: the same port twice over IPv4 and
/// IPv6, a `root` process that cannot be touched, and one that refuses to quit.
actor FakeProcessWorld {

    private var ports: [ListeningPort]
    private var processes: [pid_t: RunningProcess]

    /// Processes that shrug off `.terminate` once, so the escalation to
    /// `.forceKill` can be seen working.
    private var stubborn: Set<pid_t>

    private let scanDuration: Duration
    private let signalDuration: Duration

    init(scanDuration: Duration = .milliseconds(220),
         signalDuration: Duration = .milliseconds(320)) {
        self.scanDuration = scanDuration
        self.signalDuration = signalDuration
        self.ports = Self.samplePorts
        self.processes = Self.sampleProcesses
        self.stubborn = [7699]
    }

    func scan() async throws -> PortScan {
        try await Task.sleep(for: scanDuration)
        return PortScan(
            ports: ports,
            processes: processes,
            scannedAt: Date(),
            unreadableProcessCount: 229
        )
    }

    func send(_ signal: TerminationSignal, to pid: pid_t) async throws {
        try await Task.sleep(for: signalDuration)

        guard let process = processes[pid] else {
            throw ProcessControlError.noSuchProcess(name: "That process")
        }
        guard process.owner.isCurrentUser else {
            throw ProcessControlError.notPermitted(name: process.name)
        }
        if signal == .terminate, stubborn.contains(pid) {
            stubborn.remove(pid)
            throw ProcessControlError.ignored(name: process.name)
        }

        processes[pid] = nil
        ports.removeAll { $0.pid == pid }
    }

    /// Puts every stopped process back, for previews and repeat runs.
    func reset() {
        ports = Self.samplePorts
        processes = Self.sampleProcesses
        stubborn = [7699]
    }
}

private extension FakeProcessWorld {

    static let me = ProcessOwner(userID: getuid(), username: NSUserName())
    static let root = ProcessOwner(userID: 0, username: "root")
    static let home = NSHomeDirectory()

    static let samplePorts: [ListeningPort] = [
        ListeningPort(number: 6006, transport: .tcp, addressFamily: .ipv6, pid: 8682),
        ListeningPort(number: 5432, transport: .tcp, addressFamily: .ipv4, pid: 7712),
        ListeningPort(number: 5432, transport: .tcp, addressFamily: .ipv6, pid: 7712),
        ListeningPort(number: 27017, transport: .tcp, addressFamily: .ipv4, pid: 7699),
        ListeningPort(number: 27017, transport: .tcp, addressFamily: .ipv6, pid: 7699),
        ListeningPort(number: 5037, transport: .tcp, addressFamily: .ipv4, pid: 8571),
        ListeningPort(number: 5433, transport: .tcp, addressFamily: .ipv4, pid: 10458),
        ListeningPort(number: 6379, transport: .tcp, addressFamily: .ipv4, pid: 10458),
        ListeningPort(number: 8108, transport: .tcp, addressFamily: .ipv4, pid: 10458),
        ListeningPort(number: 631, transport: .tcp, addressFamily: .ipv4, pid: 894),
        ListeningPort(number: 7000, transport: .tcp, addressFamily: .ipv4, pid: 456),
        ListeningPort(number: 57621, transport: .udp, addressFamily: .ipv4, pid: 1122),
    ]

    static let sampleProcesses: [pid_t: RunningProcess] = [
        8682: RunningProcess(
            pid: 8682,
            parentPID: 8600,
            name: "node",
            executablePath: "/opt/homebrew/bin/node",
            owner: me,
            startedAt: Date(timeIntervalSinceNow: -4_200),
            workingDirectory: "\(home)/workspace/site",
            arguments: ["node", "\(home)/workspace/site/node_modules/.bin/vite", "--port", "6006"]
        ),
        7712: RunningProcess(
            pid: 7712,
            parentPID: 1,
            name: "postgres",
            executablePath: "/opt/homebrew/opt/postgresql@15/bin/postgres",
            owner: me,
            startedAt: Date(timeIntervalSinceNow: -86_400),
            workingDirectory: "/opt/homebrew/var/postgresql@15",
            arguments: ["/opt/homebrew/opt/postgresql@15/bin/postgres",
                        "-D", "/opt/homebrew/var/postgresql@15"]
        ),
        7699: RunningProcess(
            pid: 7699,
            parentPID: 1,
            name: "mongod",
            executablePath: "/opt/homebrew/opt/mongodb-community/bin/mongod",
            owner: me,
            startedAt: Date(timeIntervalSinceNow: -86_700),
            workingDirectory: "/opt/homebrew",
            arguments: ["/opt/homebrew/opt/mongodb-community/bin/mongod",
                        "--config", "/opt/homebrew/etc/mongod.conf"]
        ),
        8571: RunningProcess(
            pid: 8571,
            parentPID: 1,
            name: "adb",
            executablePath: "\(home)/Library/Android/sdk/platform-tools/adb",
            owner: me,
            startedAt: Date(timeIntervalSinceNow: -1_800),
            workingDirectory: "/",
            arguments: ["adb", "-L", "tcp:5037", "fork-server", "server"]
        ),
        10458: RunningProcess(
            pid: 10458,
            parentPID: 9004,
            name: "ssh",
            executablePath: "/usr/bin/ssh",
            owner: me,
            startedAt: Date(timeIntervalSinceNow: -600),
            workingDirectory: home,
            arguments: ["ssh", "-N", "-L", "5433:localhost:5432",
                        "-L", "6379:localhost:6379", "-L", "8108:localhost:8108",
                        "deploy@staging"]
        ),
        894: RunningProcess(
            pid: 894,
            parentPID: 1,
            name: "cupsd",
            executablePath: nil,
            owner: root,
            startedAt: nil,
            workingDirectory: nil,
            arguments: nil
        ),
        456: RunningProcess(
            pid: 456,
            parentPID: 1,
            name: "ControlCenter",
            executablePath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
            owner: me,
            startedAt: Date(timeIntervalSinceNow: -172_800),
            workingDirectory: "/",
            arguments: nil
        ),
        1122: RunningProcess(
            pid: 1122,
            parentPID: 1,
            name: "Spotify",
            executablePath: "/Applications/Spotify.app/Contents/MacOS/Spotify",
            owner: me,
            startedAt: Date(timeIntervalSinceNow: -9_000),
            workingDirectory: home,
            arguments: nil
        ),
    ]
}
