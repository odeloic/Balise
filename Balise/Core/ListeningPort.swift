//
//  ListeningPort.swift
//  Balise
//
//  A port that some process is listening on.
//

import Foundation

/// One socket sitting in the LISTEN state — a server waiting for connections.
///
/// Only listening sockets belong here. A browser talking to a website also owns
/// a socket, but that is an outgoing connection and is not interesting to us.
nonisolated struct ListeningPort: Identifiable, Hashable, Sendable {

    /// The port number, e.g. `5432`.
    let number: UInt16

    /// TCP or UDP.
    let transport: TransportProtocol

    /// IPv4 or IPv6.
    let addressFamily: AddressFamily

    /// The process holding this socket open.
    let pid: pid_t

    /// One process often listens on the same port twice — once over IPv4 and
    /// once over IPv6. Both are real, so the family is part of the identity.
    /// Collapse them into one row at display time, not here.
    var id: String { "\(transport.rawValue)-\(addressFamily.rawValue)-\(number)-\(pid)" }
}

nonisolated enum TransportProtocol: String, Hashable, Sendable, CaseIterable {
    case tcp
    case udp

    var label: String { rawValue.uppercased() }
}

nonisolated enum AddressFamily: String, Hashable, Sendable, CaseIterable {
    case ipv4
    case ipv6

    var label: String {
        switch self {
        case .ipv4: "IPv4"
        case .ipv6: "IPv6"
        }
    }
}
