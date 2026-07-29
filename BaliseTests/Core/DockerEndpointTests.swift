//
//  DockerEndpointTests.swift
//  BaliseTests
//

import Foundation
import Testing
@testable import Balise

@Suite("DockerEndpoint")
struct DockerEndpointTests {

    @Test("reads the host strings Docker writes", arguments: [
        ("unix:///var/run/docker.sock", DockerEndpoint.unixSocket(path: "/var/run/docker.sock")),
        ("unix:///Users/me/.colima/default/docker.sock",
         .unixSocket(path: "/Users/me/.colima/default/docker.sock")),
        ("tcp://127.0.0.1:2375", .tcp(host: "127.0.0.1", port: 2375)),
        ("http://localhost:2375", .tcp(host: "localhost", port: 2375)),
        ("ssh://deploy@staging", .unsupported(scheme: "ssh")),
        ("npipe:////./pipe/docker_engine", .unsupported(scheme: "npipe")),
    ])
    func parses(hostString: String, expected: DockerEndpoint) {
        #expect(DockerEndpoint(hostString: hostString) == expected)
    }

    @Test("a missing port falls back to the scheme's default", arguments: [
        ("tcp://example.com", 2375),
        ("http://example.com", 2375),
        ("https://example.com", 2376),
    ])
    func defaultPort(hostString: String, expected: Int) {
        #expect(DockerEndpoint(hostString: hostString) == .tcp(host: "example.com", port: expected))
    }

    @Test("an IPv6 literal keeps its brackets")
    func ipv6WithPort() throws {
        let endpoint = try #require(DockerEndpoint(hostString: "tcp://[::1]:2375"))
        #expect(endpoint == .tcp(host: "[::1]", port: 2375))
    }

    /// Splitting on the last colon finds one inside the address itself. The
    /// piece after it is not a number, so the whole thing stays the host.
    @Test("an IPv6 literal with no port is left whole")
    func ipv6WithoutPort() {
        #expect(DockerEndpoint(hostString: "tcp://[::1]") == .tcp(host: "[::1]", port: 2375))
    }

    @Test("the scheme is not case sensitive")
    func uppercaseScheme() {
        #expect(DockerEndpoint(hostString: "UNIX:///tmp/d.sock") == .unixSocket(path: "/tmp/d.sock"))
    }

    @Test("surrounding whitespace is ignored")
    func trimsWhitespace() {
        #expect(DockerEndpoint(hostString: "  unix:///tmp/d.sock\n") == .unixSocket(path: "/tmp/d.sock"))
    }

    @Test("nonsense returns nothing", arguments: [
        "/var/run/docker.sock",
        "unix://",
        "://localhost",
        "",
    ])
    func rejects(hostString: String) {
        #expect(DockerEndpoint(hostString: hostString) == nil)
    }

    @Test("only a socket or a network address can be reached")
    func reachability() {
        #expect(DockerEndpoint.unixSocket(path: "/tmp/d.sock").isReachable)
        #expect(DockerEndpoint.tcp(host: "localhost", port: 2375).isReachable)
        #expect(!DockerEndpoint.unsupported(scheme: "ssh").isReachable)
    }

    @Test("description says something the user can act on")
    func descriptions() {
        #expect(DockerEndpoint.unixSocket(path: "/tmp/d.sock").description == "/tmp/d.sock")
        #expect(DockerEndpoint.tcp(host: "localhost", port: 2375).description == "localhost:2375")
        #expect(DockerEndpoint.unsupported(scheme: "ssh").description == "ssh:// (not supported)")
    }
}
