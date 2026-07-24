//
//  PortRowView.swift
//  Balise
//

import AppKit
import SwiftUI

struct PortRowView: View {

    let row: ProcessRow
    let isExpanded: Bool
    let isStopping: Bool
    let onToggle: () -> Void
    let onStop: (TerminationSignal) -> Void

    private let iconColumn: CGFloat = 20
    private let portColumn: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if isExpanded { details }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isExpanded ? Color.accentColor.opacity(0.12) : .clear)
        .contentShape(.rect)
        .onTapGesture(perform: onToggle)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            Image(systemName: row.source.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(row.source.tint)
                .frame(width: iconColumn)

            Text(String(row.port.number))
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: portColumn, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
    }

    private var subtitle: String {
        var parts = [row.source.label, row.port.addressFamily.label]
        if row.port.transport == .udp { parts.append(row.port.transport.label) }
        if !row.canStop { parts.append(row.ownerLabel) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailing: some View {
        if isStopping {
            ProgressView().controlSize(.small)
        } else if row.canStop {
            Image(systemName: "stop.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailGrid
            actions
        }
        .padding(.top, 10)
        .padding(.leading, iconColumn + 10)
        .padding(.bottom, 2)
    }

    private var detailGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
            detailLine("Process ID", String(row.pid))
            detailLine("Owner", row.ownerLabel)
            if let path = row.process?.executablePath {
                detailLine("Path", path)
            }
            if let folder = row.process?.workingDirectory {
                detailLine("Folder", folder)
            }
            if let arguments = row.process?.arguments, !arguments.isEmpty {
                detailLine("Command", arguments.joined(separator: " "))
            }
            if let started = row.process?.startedAt {
                detailLine("Started", started.formatted(.relative(presentation: .named)))
            }
        }
        .font(.caption)
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(value)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Copy Port") { copy(String(row.port.number)) }
            Button("Copy PID") { copy(String(row.pid)) }

            Spacer(minLength: 4)

            if row.canStop {
                Button("Quit", role: .destructive) { onStop(.terminate) }
                    .disabled(isStopping)
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
