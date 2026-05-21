//
//  CloudSyncDiagnosticsView.swift
//  SportsCal
//
//  Inspector for the iCloud Key-Value Store sync used by CloudSyncManager.
//  Shows account state, last push/pull timestamps, and a side-by-side compare
//  of every synced key's local value vs. its cloud value. Useful for verifying
//  iOS↔Mac preference sync.
//

import SwiftUI

struct CloudSyncDiagnosticsView: View {
    @State private var diagnostics = CloudSyncManager.shared.currentDiagnostics()
    @State private var refreshTimer: Timer?

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("iCloud signed in", value: diagnostics.iCloudAccountAvailable ? "Yes" : "No")
                LabeledContent("Bundle identifier", value: diagnostics.bundleIdentifier)
                LabeledContent("KVS container", value: diagnostics.kvStoreIdentifier)
                #if os(iOS)
                LabeledContent("Platform", value: "iOS")
                #elseif os(macOS)
                LabeledContent("Platform", value: "macOS")
                #else
                LabeledContent("Platform", value: "other")
                #endif
            }

            Section("Sync activity") {
                LabeledContent("Last push", value: format(diagnostics.lastPushDate))
                LabeledContent("Last remote update", value: format(diagnostics.lastRemoteUpdateDate))
                LabeledContent("Cloud timestamp", value: format(diagnostics.cloudTimestamp))
                LabeledContent("Last change reason", value: reasonText(diagnostics.lastRemoteChangeReason))
            }

            Section("Actions") {
                Button("Refresh") { refresh() }
                Button("Force push to iCloud") {
                    CloudSyncManager.shared.forcePushAll()
                    refresh()
                }
                Button("Force pull from iCloud") {
                    CloudSyncManager.shared.forcePullAll()
                    refresh()
                }
            }

            Section("Per-key state") {
                ForEach(diagnostics.entries) { entry in
                    DiagnosticEntryRow(entry: entry)
                }
            }
        }
        .navigationTitle("iCloud Sync")
        .onAppear {
            refresh()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                refresh()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func refresh() {
        diagnostics = CloudSyncManager.shared.currentDiagnostics()
    }

    private func format(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: date)
    }

    private func reasonText(_ reason: Int?) -> String {
        guard let reason else { return "—" }
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange: return "Server change"
        case NSUbiquitousKeyValueStoreInitialSyncChange: return "Initial sync"
        case NSUbiquitousKeyValueStoreQuotaViolationChange: return "Quota violation"
        case NSUbiquitousKeyValueStoreAccountChange: return "Account change"
        default: return "Reason \(reason)"
        }
    }
}

private struct DiagnosticEntryRow: View {
    let entry: CloudSyncManager.Diagnostics.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.key)
                    .font(.subheadline.monospaced())
                Spacer()
                Image(systemName: entry.inSync ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(entry.inSync ? .green : .orange)
            }
            Text("local: \(entry.localValue)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("cloud: \(entry.cloudValue)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        CloudSyncDiagnosticsView()
    }
}
