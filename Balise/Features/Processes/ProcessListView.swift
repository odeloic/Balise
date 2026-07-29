//
//  ProcessListView.swift
//  Balise
//

import AppKit
import SwiftUI

struct ProcessListView: View {

    @Bindable var store: ProcessListStore
    @State private var expanded: Set<String> = []
    @State private var contentHeight: CGFloat = 0

    private let width: CGFloat = 360

    /// The popover hangs off the menu bar, so an unbounded list runs off the
    /// bottom of the screen — 30 listening ports is taller than a laptop
    /// display. The ceiling comes from the display rather than a fixed number,
    /// and the allowance covers the header, the footer and room above the Dock.
    /// The second number is taste: a menu should not fill the whole screen.
    private var maxListHeight: CGFloat {
        let usable = NSScreen.main?.visibleFrame.height ?? 700
        return min(usable - 200, 560)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: width)
        .task { await store.refresh() }
        .confirmationDialog(
            forceQuitTitle,
            isPresented: forceQuitPresented,
            presenting: store.forceQuitCandidate
        ) { row in
            Button("Force Quit", role: .destructive) {
                store.forceQuitCandidate = nil
                Task { await store.stop(row, using: .forceKill) }
            }
            Button("Cancel", role: .cancel) { store.forceQuitCandidate = nil }
        } message: { row in
            Text("\(row.name) ignored the request to quit. Forcing it will lose anything unsaved.")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Ports")
                .font(.headline)

            if !store.rows.isEmpty {
                Text(String(store.rows.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(store.loadState == .loading)
            .help("Scan again")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if case .failed(let message) = store.loadState {
            VStack(spacing: 8) {
                placeholder(symbol: "exclamationmark.triangle", title: message)
                Button("Try Again") { Task { await store.refresh() } }
                    .controlSize(.small)
            }
            .padding(.bottom, 16)
        } else if !store.rows.isEmpty {
            rowList
        } else if store.isEmpty {
            placeholder(symbol: "moon.zzz", title: "Nothing is listening")
        } else {
            placeholder(symbol: "hourglass", title: "Scanning…")
        }
    }

    private var rowList: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(store.rows) { row in
                    if row.id != store.rows.first?.id {
                        Divider().padding(.leading, 42)
                    }
                    PortRowView(
                        row: row,
                        isExpanded: expanded.contains(row.id),
                        isStopping: store.stopping.contains(row.pid),
                        onToggle: { toggle(row) },
                        onStop: { signal in
                            Task { await store.stop(row, using: signal) }
                        }
                    )
                }
            }
            .frame(width: width, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: listHeight)
        .mask(bottomFade)
    }

    /// A `ScrollView` claims no height of its own inside a window that sizes to
    /// fit, so it has to be told one. The rows are measured, then the list takes
    /// exactly that much until it hits the ceiling. The estimate covers the
    /// first pass, before anything has been laid out.
    private var listHeight: CGFloat {
        let measured = contentHeight > 0 ? contentHeight : CGFloat(store.rows.count) * 46
        return min(measured, maxListHeight)
    }

    private var isScrollable: Bool { contentHeight > maxListHeight + 1 }

    /// With no scrollbar there is nothing to say the list continues, so the
    /// last row is faded out instead — but only when there is more to reach.
    @ViewBuilder
    private var bottomFade: some View {
        if isScrollable {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.9),
                    .init(color: .black.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Rectangle()
        }
    }

    private func placeholder(symbol: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button("Quit Balise") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .keyboardShortcut("q")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var footerText: String {
        guard store.scannedAt != nil else { return " " }
        return "\(store.unreadableProcessCount) processes need higher access"
    }

    private var forceQuitTitle: String {
        store.forceQuitCandidate.map { "Force \($0.name) to quit?" } ?? ""
    }

    private var forceQuitPresented: Binding<Bool> {
        Binding(
            get: { store.forceQuitCandidate != nil },
            set: { if !$0 { store.forceQuitCandidate = nil } }
        )
    }

    private func toggle(_ row: ProcessRow) {
        if expanded.contains(row.id) {
            expanded.remove(row.id)
        } else {
            expanded.insert(row.id)
        }
    }
}

#Preview {
    let world = FakeProcessWorld()
    ProcessListView(store: ProcessListStore(
        inspector: PreviewProcessInspector(world: world),
        controller: PreviewProcessController(world: world)
    ))
}
