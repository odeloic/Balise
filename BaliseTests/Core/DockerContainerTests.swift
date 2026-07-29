//
//  DockerContainerTests.swift
//  BaliseTests
//

import Foundation
import Testing
@testable import Balise

@Suite("DockerContainer")
struct DockerContainerTests {

    private func container(
        id: String = String(repeating: "a", count: 64),
        state: DockerContainer.State = .running,
        publishedPorts: [PublishedPort] = []
    ) -> DockerContainer {
        DockerContainer(
            id: id,
            name: "postgres-dev",
            image: "postgres:16",
            state: state,
            status: "Up 3 hours",
            publishedPorts: publishedPorts,
            createdAt: nil
        )
    }

    @Test("the short id is the first twelve characters, same as the docker command")
    func shortID() {
        let full = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        #expect(container(id: full).shortID == "0123456789ab")
    }

    @Test("a container doing work can be stopped", arguments: [
        (DockerContainer.State.running, true),
        (.restarting, true),
        (.paused, true),
        (.created, false),
        (.exited, false),
        (.dead, false),
        (.removing, false),
    ])
    func activeStates(state: DockerContainer.State, expected: Bool) {
        #expect(state.isActive == expected)
    }

    @Test("every state Docker reports is covered")
    func allStatesHandled() {
        #expect(DockerContainer.State.allCases.count == 7)
        #expect(DockerContainer.State(rawValue: "running") == .running)
    }

    @Test("a published port is identified by both sides and the transport")
    func publishedPortIdentity() {
        let tcp = PublishedPort(hostPort: 5432, containerPort: 5432, transport: .tcp)
        let udp = PublishedPort(hostPort: 5432, containerPort: 5432, transport: .udp)

        #expect(tcp.id == "5432-5432-tcp")
        #expect(tcp.id != udp.id)
    }
}

@Suite("ContainerResourceUsage")
struct ContainerResourceUsageTests {

    private func usage(used: UInt64, limit: UInt64?) -> ContainerResourceUsage {
        ContainerResourceUsage(
            containerID: "abc",
            cpuShare: 0.25,
            memoryUsedBytes: used,
            memoryLimitBytes: limit
        )
    }

    @Test("memory share is used over limit")
    func share() {
        #expect(usage(used: 512, limit: 1024).memoryShare == 0.5)
    }

    @Test("no limit means no share to report")
    func unlimited() {
        #expect(usage(used: 512, limit: nil).memoryShare == nil)
    }

    /// Docker reports zero for some setups. Dividing by it would give infinity
    /// or a crash, so it is treated as no limit at all.
    @Test("a zero limit is not a divide by zero")
    func zeroLimit() {
        #expect(usage(used: 512, limit: 0).memoryShare == nil)
    }
}
