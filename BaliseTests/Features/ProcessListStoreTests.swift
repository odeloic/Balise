//
//  ProcessListStoreTests.swift
//  BaliseTests
//

import Foundation
import Testing
@testable import Balise

@Suite("ProcessListStore")
struct ProcessListStoreTests {

    private func store(
        inspector: any ProcessInspecting,
        controller: any ProcessControlling = RecordingProcessController()
    ) -> ProcessListStore {
        ProcessListStore(inspector: inspector, controller: controller)
    }

    @Test("a store starts with nothing and no opinion")
    func initialState() {
        let store = store(inspector: StubProcessInspector())

        #expect(store.rows.isEmpty)
        #expect(store.loadState == .idle)
        #expect(store.scannedAt == nil)
        #expect(store.lastError == nil)
        #expect(!store.isEmpty)
    }

    @Test("a refresh loads sorted rows and the scan's own numbers")
    func refreshLoads() async {
        let scan = Fixture.scan(
            ports: [Fixture.port(8080, pid: 11), Fixture.port(5432, pid: 10)],
            processes: [Fixture.process(pid: 10, name: "postgres"),
                        Fixture.process(pid: 11, name: "node")],
            unreadableProcessCount: 229
        )
        let store = store(inspector: StubProcessInspector(result: scan))

        await store.refresh()

        #expect(store.loadState == .loaded)
        #expect(store.rows.map(\.name) == ["postgres", "node"])
        #expect(store.unreadableProcessCount == 229)
        #expect(store.scannedAt == scan.scannedAt)
    }

    @Test("a scan that fails leaves a message, not a crash")
    func refreshFails() async {
        let inspector = StubProcessInspector(failure: StubError(message: "libproc said no"))
        let store = store(inspector: inspector)

        await store.refresh()

        #expect(store.loadState == .failed("libproc said no"))
        #expect(store.rows.isEmpty)
    }

    @Test("empty only counts once a scan has actually finished")
    func emptyNeedsALoad() async {
        let store = store(inspector: StubProcessInspector())
        #expect(!store.isEmpty)

        await store.refresh()
        #expect(store.isEmpty)
    }

    @Test("a refresh already in flight is not started again", .timeLimit(.minutes(1)))
    func refreshIsNotReentrant() async {
        let inspector = GatedProcessInspector()
        let store = store(inspector: inspector)

        let first = Task { await store.refresh() }
        await inspector.waitUntilScanning()
        #expect(store.loadState == .loading)

        await store.refresh()
        #expect(await inspector.scanCount == 1)

        await inspector.finish()
        await first.value
        #expect(store.loadState == .loaded)
    }

    @Test("a successful stop rescans so the row disappears")
    func stopRemovesTheRow() async throws {
        let world = FakeProcessWorld(scanDuration: .zero, signalDuration: .zero)
        let store = store(inspector: PreviewProcessInspector(world: world),
                          controller: PreviewProcessController(world: world))

        await store.refresh()
        let row = try #require(store.rows.first { $0.pid == 8682 })

        await store.stop(row, using: .terminate)

        #expect(!store.rows.contains { $0.pid == 8682 })
        #expect(store.lastError == nil)
    }

    /// A process is allowed to ignore a polite request. The store does not
    /// treat that as an error — it hands the row to the view, which offers
    /// force quit.
    @Test("a process that ignores quit becomes a force quit candidate")
    func stubbornProcessEscalates() async throws {
        let world = FakeProcessWorld(scanDuration: .zero, signalDuration: .zero)
        let store = store(inspector: PreviewProcessInspector(world: world),
                          controller: PreviewProcessController(world: world))

        await store.refresh()
        let row = try #require(store.rows.first { $0.pid == 7699 })

        await store.stop(row, using: .terminate)

        #expect(store.forceQuitCandidate?.pid == 7699)
        #expect(store.lastError == nil)
        #expect(store.rows.contains { $0.pid == 7699 })

        await store.stop(row, using: .forceKill)
        #expect(!store.rows.contains { $0.pid == 7699 })
    }

    @Test("another user's process never reaches the controller")
    func rootProcessIsNotSignalled() async throws {
        let scan = Fixture.scan(
            ports: [Fixture.port(631, pid: 894)],
            processes: [Fixture.process(pid: 894, name: "cupsd",
                                        executablePath: nil, owner: Fixture.root)]
        )
        let controller = RecordingProcessController()
        let store = store(inspector: StubProcessInspector(result: scan), controller: controller)

        await store.refresh()
        let row = try #require(store.rows.first)

        await store.stop(row, using: .forceKill)

        #expect(await controller.calls.isEmpty)
        #expect(store.lastError == nil)
        #expect(store.rows.count == 1)
    }

    @Test("a refused stop shows a message and keeps the list")
    func refusedStopKeepsTheList() async throws {
        let scan = Fixture.scan(
            ports: [Fixture.port(5432, pid: 10)],
            processes: [Fixture.process(pid: 10, name: "postgres")]
        )
        let controller = RecordingProcessController(
            failures: [ProcessControlError.notPermitted(name: "postgres")]
        )
        let store = store(inspector: StubProcessInspector(result: scan), controller: controller)

        await store.refresh()
        let row = try #require(store.rows.first)

        await store.stop(row, using: .terminate)

        #expect(store.lastError == "postgres belongs to another user. Balise cannot stop it.")
        #expect(store.loadState == .loaded)
        #expect(store.rows.count == 1)
    }

    /// A process can exit between the scan and the click. That is not worth a
    /// message — the list just catches up.
    @Test("a process that already died is only a rescan")
    func alreadyGoneIsQuiet() async throws {
        let scan = Fixture.scan(
            ports: [Fixture.port(5432, pid: 10)],
            processes: [Fixture.process(pid: 10, name: "postgres")]
        )
        let controller = RecordingProcessController(
            failures: [ProcessControlError.noSuchProcess(name: "postgres")]
        )
        let store = store(inspector: StubProcessInspector(result: scan), controller: controller)

        await store.refresh()
        let row = try #require(store.rows.first)

        await store.stop(row, using: .terminate)

        #expect(store.lastError == nil)
        #expect(store.loadState == .loaded)
    }

    @Test("the signal the view picked is the signal that gets sent")
    func signalIsPassedThrough() async throws {
        let scan = Fixture.scan(
            ports: [Fixture.port(5432, pid: 10)],
            processes: [Fixture.process(pid: 10)]
        )
        let controller = RecordingProcessController()
        let store = store(inspector: StubProcessInspector(result: scan), controller: controller)

        await store.refresh()
        let row = try #require(store.rows.first)

        await store.stop(row, using: .forceKill)

        #expect(await controller.calls == [.init(signal: .forceKill, pid: 10)])
    }
}
