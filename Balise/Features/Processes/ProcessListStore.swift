//
//  ProcessListStore.swift
//  Balise
//
//  Holds what the port list shows and what its buttons do.
//

import Foundation
import Observation

@Observable
final class ProcessListStore {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var rows: [ProcessRow] = []
    private(set) var loadState: LoadState = .idle
    private(set) var scannedAt: Date?
    private(set) var unreadableProcessCount = 0

    /// Processes with a signal in flight, so their row can show a spinner.
    private(set) var stopping: Set<pid_t> = []

    /// A failed action. Kept apart from `loadState` so a refused Stop does not
    /// wipe out a list that is otherwise fine.
    var lastError: String?

    /// Set when a process ignored `.terminate`. The view turns this into a
    /// "Force Quit?" prompt.
    var forceQuitCandidate: ProcessRow?

    private let inspector: ProcessInspecting
    private let controller: ProcessControlling

    init(inspector: ProcessInspecting, controller: ProcessControlling) {
        self.inspector = inspector
        self.controller = controller
    }

    var isEmpty: Bool { rows.isEmpty && loadState == .loaded }

    func refresh() async {
        guard loadState != .loading else { return }
        loadState = .loading

        do {
            let scan = try await inspector.scan()
            rows = scan.rows
            scannedAt = scan.scannedAt
            unreadableProcessCount = scan.unreadableProcessCount
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func stop(_ row: ProcessRow, using signal: TerminationSignal) async {
        guard row.canStop, !stopping.contains(row.pid) else { return }

        lastError = nil
        stopping.insert(row.pid)
        defer { stopping.remove(row.pid) }

        do {
            try await controller.send(signal, to: row.pid)
            await refresh()
        } catch ProcessControlError.ignored {
            forceQuitCandidate = row
        } catch ProcessControlError.noSuchProcess {
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
