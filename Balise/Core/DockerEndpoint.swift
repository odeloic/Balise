//
//  DockerEndpoint.swift
//  Balise
//
//  Where the Docker engine can be reached on this Mac.
//

import Foundation

/// The address of a Docker engine.
///
/// There is no single right answer here. Docker Desktop, Colima, OrbStack,
/// Rancher and Podman all put their socket somewhere different, and the user
/// can point at a remote machine. Finding the value is the job of a service
/// in `Services/Docker/`; this type only describes the result.
nonisolated enum DockerEndpoint: Hashable, Sendable {

    /// A file socket on this Mac. The common case.
    case unixSocket(path: String)

    /// A network address. Used for remote engines and some Windows setups.
    case tcp(host: String, port: Int)

    /// A shape we understand but cannot reach, such as `ssh://`.
    ///
    /// Reaching an `ssh://` engine means running a tunnel, which Balise does
    /// not do. Keeping it as a case lets the interface explain itself instead
    /// of silently showing no containers.
    case unsupported(scheme: String)

    /// Reads one of the host strings Docker writes into its config,
    /// e.g. `unix:///Users/me/.colima/default/docker.sock`.
    ///
    /// Returns `nil` only when the string has no scheme at all.
    init?(hostString: String) {
        let trimmed = hostString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.range(of: "://") else { return nil }

        let scheme = String(trimmed[trimmed.startIndex..<separator.lowerBound]).lowercased()
        let remainder = String(trimmed[separator.upperBound...])
        guard !scheme.isEmpty else { return nil }

        switch scheme {
        case "unix":
            // `unix:///var/run/docker.sock` has three slashes: the third one
            // starts the absolute path, so `remainder` is already the path.
            guard !remainder.isEmpty else { return nil }
            self = .unixSocket(path: remainder)

        case "tcp", "http", "https":
            let defaultPort = (scheme == "https") ? 2376 : 2375
            // Split on the last colon so IPv6 literals like `[::1]:2375` survive.
            if let colon = remainder.lastIndex(of: ":"),
               let port = Int(remainder[remainder.index(after: colon)...]) {
                self = .tcp(host: String(remainder[..<colon]), port: port)
            } else {
                self = .tcp(host: remainder, port: defaultPort)
            }

        default:
            self = .unsupported(scheme: scheme)
        }
    }

    /// True when Balise can actually connect to this endpoint today.
    var isReachable: Bool {
        switch self {
        case .unixSocket, .tcp: true
        case .unsupported: false
        }
    }

    /// Text to show the user when things go wrong.
    var description: String {
        switch self {
        case .unixSocket(let path): path
        case .tcp(let host, let port): "\(host):\(port)"
        case .unsupported(let scheme): "\(scheme):// (not supported)"
        }
    }
}
