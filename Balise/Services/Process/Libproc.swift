//
//  Libproc.swift
//  Balise
//
//  Thin wrappers over the C process APIs. Buffers and system calls, nothing else.
//

import Darwin
import Foundation

/// Every call here is a system call. Nothing decides anything; the service on
/// top does that. Kept separate so the awkward C parts stay in one file.
nonisolated enum Libproc {

    /// A listening socket, before we know whose it is.
    struct Socket: Hashable, Sendable {
        let port: UInt16
        let transport: TransportProtocol
        let family: AddressFamily
    }

    struct BSDInfo: Hashable, Sendable {
        let parentPID: pid_t
        let name: String
        let userID: uid_t
        let startedAt: Date
    }

    /// The little that macOS will tell anyone about any process.
    struct ShortInfo: Hashable, Sendable {
        let parentPID: pid_t
        let name: String
        let userID: uid_t
    }

    static func allPIDs() -> [pid_t] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [] }

        // The list can grow between the two calls, so ask for extra room.
        let capacity = Int(byteCount) / MemoryLayout<pid_t>.size + 64
        var pids = [pid_t](repeating: 0, count: capacity)

        let written = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress,
                          Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard written > 0 else { return [] }

        return pids.prefix(Int(written) / MemoryLayout<pid_t>.size).filter { $0 > 0 }
    }

    /// Sockets this process is listening on.
    ///
    /// `nil` means macOS refused to open the process, which is the normal
    /// answer for anything owned by `root` or another user. An empty array
    /// means it was readable and holds nothing.
    ///
    /// A refusal comes back as `0` with `EPERM`, not as `-1`. Measured on this
    /// Mac: 246 of 791 processes answer that way, none of them ours.
    static func listeningSockets(of pid: pid_t) -> [Socket]? {
        errno = 0
        let byteCount = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard byteCount > 0 else { return errno == EPERM ? nil : [] }

        let stride = MemoryLayout<proc_fdinfo>.size
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(byteCount) / stride + 16)

        let written = descriptors.withUnsafeMutableBufferPointer { buffer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress,
                         Int32(buffer.count * stride))
        }
        guard written > 0 else { return nil }

        var sockets: [Socket] = []
        for descriptor in descriptors.prefix(Int(written) / stride)
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            if let socket = listeningSocket(pid: pid, fd: descriptor.proc_fd) {
                sockets.append(socket)
            }
        }
        return sockets
    }

    static func bsdInfo(of pid: pid_t) -> BSDInfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)

        let read = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, size)
        }
        guard read == size else { return nil }

        let registered = text(info.pbi_name)
        return BSDInfo(
            parentPID: pid_t(bitPattern: info.pbi_ppid),
            name: registered.isEmpty ? text(info.pbi_comm) : registered,
            userID: info.pbi_uid,
            startedAt: Date(timeIntervalSince1970: Double(info.pbi_start_tvsec)
                            + Double(info.pbi_start_tvusec) / 1_000_000)
        )
    }

    /// Works where `bsdInfo` does not.
    ///
    /// `PROC_PIDTBSDINFO` is refused for anything outside your own account —
    /// `launchd` answers `EPERM`. This flavour answers for everything, which
    /// is how a stop button can name the process it was not allowed to stop.
    static func shortInfo(of pid: pid_t) -> ShortInfo? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)

        let read = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, $0, size)
        }
        guard read == size else { return nil }

        return ShortInfo(
            parentPID: pid_t(bitPattern: info.pbsi_ppid),
            name: text(info.pbsi_comm),
            userID: info.pbsi_uid
        )
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(MAXPATHLEN))
        guard length > 0 else { return nil }
        return String(decoding: buffer[..<Int(length)], as: UTF8.self)
    }

    static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)

        let read = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, $0, size)
        }
        guard read == size else { return nil }

        let path = text(info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    /// The full command line.
    ///
    /// This is a `sysctl`, not a libproc call, and it costs far more than
    /// everything else here. Only ask for processes that made it into a scan.
    /// Returns `nil` for anything not owned by the current user.
    static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var byteCount = 0
        guard sysctl(&mib, 3, nil, &byteCount, nil, 0) == 0, byteCount > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: byteCount)
        guard sysctl(&mib, 3, &buffer, &byteCount, nil, 0) == 0 else { return nil }

        return parseArguments(buffer, byteCount: byteCount)
    }

    static func username(for userID: uid_t) -> String? {
        guard let entry = getpwuid(userID) else { return nil }
        return String(cString: entry.pointee.pw_name)
    }

    /// True when a process with this id exists. `EPERM` still means alive —
    /// it belongs to somebody else.
    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

extension Libproc {

    /// Reads `KERN_PROCARGS2`, whose shape is:
    /// a four byte count, the executable path, a run of padding zeros, then
    /// that many null-terminated arguments.
    static func parseArguments(_ buffer: [UInt8], byteCount: Int) -> [String]? {
        let header = MemoryLayout<Int32>.size
        let end = min(byteCount, buffer.count)
        guard end > header else { return nil }

        let count = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard count > 0 else { return nil }

        var cursor = header
        while cursor < end, buffer[cursor] != 0 { cursor += 1 }
        while cursor < end, buffer[cursor] == 0 { cursor += 1 }

        var arguments: [String] = []
        while arguments.count < Int(count), cursor < end {
            var stop = cursor
            while stop < end, buffer[stop] != 0 { stop += 1 }
            arguments.append(String(decoding: buffer[cursor..<stop], as: UTF8.self))
            cursor = stop + 1
        }
        return arguments.isEmpty ? nil : arguments
    }

    /// Reads a fixed-size C character array up to its first zero byte.
    /// Stays inside the array even when nothing terminates it.
    static func text<Bytes>(_ value: Bytes) -> String {
        withUnsafeBytes(of: value) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Ports arrive in network byte order inside an `int`.
    static func hostPort(_ raw: Int32) -> UInt16 {
        UInt16(bigEndian: UInt16(truncatingIfNeeded: raw))
    }

    private static func listeningSocket(pid: pid_t, fd: Int32) -> Socket? {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.size)

        let read = withUnsafeMutablePointer(to: &info) {
            proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, $0, size)
        }
        guard read == size else { return nil }

        let family: AddressFamily
        switch info.psi.soi_family {
        case AF_INET: family = .ipv4
        case AF_INET6: family = .ipv6
        default: return nil
        }

        switch info.psi.soi_kind {
        case Int32(SOCKINFO_TCP):
            let tcp = info.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == TSI_S_LISTEN else { return nil }
            let port = hostPort(tcp.tcpsi_ini.insi_lport)
            return port == 0 ? nil : Socket(port: port, transport: .tcp, family: family)

        case Int32(SOCKINFO_IN):
            // UDP has no listen state. A bound local port with no foreign port
            // is the closest thing to a server waiting for packets.
            guard info.psi.soi_protocol == Int32(IPPROTO_UDP) else { return nil }
            let inet = info.psi.soi_proto.pri_in
            guard inet.insi_fport == 0 else { return nil }
            let port = hostPort(inet.insi_lport)
            return port == 0 ? nil : Socket(port: port, transport: .udp, family: family)

        default:
            return nil
        }
    }
}
