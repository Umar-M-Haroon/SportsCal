//
//  DebugLiveActivityTestView.swift
//  SportsCal (iOS)
//
//  Dedicated test dashboard for the auto-follow → push-to-start live activity flow.
//

import SwiftUI
import SportsCalModel
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

struct DebugLiveActivityTestView: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var appStorage
    @State private var selectedSport: SportType = .basketball
    @State private var serverStatus: NetworkHandler.DeviceRegistrationStatus?
    @State private var serverStatusLoading = false
    @State private var serverStatusError: String?

    var body: some View {
        Form {
            // MARK: - Create Fake Game
            Section("Create Fake Game") {
                Picker("Sport", selection: $selectedSport) {
                    ForEach(SportType.allCases, id: \.self) { sport in
                        Text(sport.displayName).tag(sport)
                    }
                }

                Button("Create Fake Upcoming Game") {
                    viewModel.injectFakeUpcomingGame(sport: selectedSport)
                }
            }

            // MARK: - Fake Games
            if !viewModel.debugFakeGames.isEmpty {
                Section("Fake Games") {
                    ForEach(viewModel.debugFakeGames, id: \.id) { game in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(game.strHomeTeam)
                                    .font(.subheadline.bold())
                                Text("vs")
                                    .foregroundColor(.secondary)
                                Text(game.strAwayTeam)
                                    .font(.subheadline.bold())
                            }
                            HStack(spacing: 6) {
                                Text(game.idEvent ?? "")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                if let eventID = game.idEvent, appStorage.isAutoFollowing(eventID) {
                                    Text("AUTO-FOLLOW")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .background(.blue, in: RoundedRectangle(cornerRadius: 4))
                                }
                            }

                            if let eventID = game.idEvent, !appStorage.isAutoFollowing(eventID) {
                                Button("Auto-Follow") {
                                    appStorage.addAutoFollow(eventID)
                                    #if os(iOS)
                    viewModel.sendAutoFollowRegistration()
                    #endif
                                    AutoFollowLogger.shared.log("Auto-follow added: \(eventID)")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // MARK: - Auto-Follow State
            Section("Auto-Follow State") {
                Text("Auto-follow event IDs: \(appStorage.autoFollowEventIDs.count)")
                if !appStorage.autoFollowEventIDs.isEmpty {
                    ForEach(Array(appStorage.autoFollowEventIDs), id: \.self) { id in
                        Text(id)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                Toggle("Auto-follow favorites", isOn: Bindable(appStorage).autoFollowFavorites)
            }

            // MARK: - Live Activities
            #if canImport(ActivityKit) && os(iOS)
            Section("Live Activities") {
                let activities = Activity<LiveSportActivityAttributes>.activities
                Text("Active: \(activities.count)")
                ForEach(Array(activities), id: \.id) { activity in
                    VStack(alignment: .leading) {
                        Text("\(activity.attributes.homeTeam) vs \(activity.attributes.awayTeam)")
                            .font(.subheadline)
                        Text("Event: \(activity.attributes.eventID)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
            }
            #endif

            // MARK: - Pipeline Checklist
            Section("Pipeline Checklist") {
                pipelineRow(step: "Push-to-start token obtained", ok: viewModel.currentPushToStartToken != nil, detail: viewModel.currentPushToStartToken.map { String($0.prefix(12)) + "..." } ?? "No token")
                pipelineRow(step: "Token registered with server", ok: serverStatus?.registered == true, detail: serverStatus?.registered == true ? "Registered" : "Not registered")
                pipelineRow(step: "Event IDs sent to server", ok: (serverStatus?.eventIDs.count ?? 0) > 0, detail: "\(serverStatus?.eventIDs.count ?? 0) event(s)")
                pipelineRow(step: "Server has APNS ready", ok: serverStatus?.apnsConfigured == true, detail: serverStatus?.apnsConfigured == true ? "Configured" : "Not configured")
                pipelineRow(step: "Notification delivered", ok: (serverStatus?.sentNotifications.count ?? 0) > 0, detail: "\(serverStatus?.sentNotifications.count ?? 0) sent")

                Button("Refresh Pipeline Status") {
                    fetchServerStatus()
                }
                .disabled(viewModel.currentPushToStartToken == nil)

                if serverStatusLoading {
                    ProgressView("Checking server...")
                } else if let error = serverStatusError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // MARK: - Server Registration Details
            if let status = serverStatus, status.registered {
                Section("Server Registration Details") {
                    LabeledContent("APNS Configured", value: status.apnsConfigured ? "Yes" : "No")
                    if !status.favorites.isEmpty {
                        LabeledContent("Favorites") {
                            Text(status.favorites.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !status.eventIDs.isEmpty {
                        LabeledContent("Event IDs") {
                            VStack(alignment: .trailing) {
                                ForEach(status.eventIDs, id: \.self) { id in
                                    Text(id).font(.caption.monospaced())
                                }
                            }
                        }
                    }
                    LabeledContent("Sent Notifications", value: "\(status.sentNotifications.count)")
                }
            }

            // MARK: - Event Log
            Section("Event Log") {
                let logger = AutoFollowLogger.shared
                if logger.entries.isEmpty {
                    Text("No events yet")
                        .foregroundColor(.secondary)
                } else {
                    Button("Clear Log") { logger.clear() }
                    ForEach(logger.entries.reversed()) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.level.symbol)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.message)
                                    .font(.caption)
                                Text(entry.date.formatted(.dateTime.hour().minute().second()))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // MARK: - Cleanup
            Section {
                Button("Clear All Debug Games", role: .destructive) {
                    viewModel.clearDebugFakeGames()
                }
            }

            // MARK: - Test Instructions
            Section("How to Test Push-to-Start") {
                VStack(alignment: .leading, spacing: 8) {
                    instructionRow(step: 1, text: "Create a fake game and tap Auto-Follow")
                    instructionRow(step: 2, text: "Refresh Pipeline — all steps should be green")
                    instructionRow(step: 3, text: "Force-quit the app")
                    instructionRow(step: 4, text: "Open admin dashboard > Debug Tools")
                    instructionRow(step: 5, text: "Click the event ID, then Send Push-to-Start")
                    instructionRow(step: 6, text: "Live Activity appears on lock screen")
                }
                .font(.caption)
            }
        }
        .navigationTitle("Live Activity Testing")
    }

    // MARK: - Helpers

    private func pipelineRow(step: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.green : Color.red.opacity(0.6))
                .frame(width: 10, height: 10)
            Text(step)
                .font(.subheadline)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func fetchServerStatus() {
        guard let token = viewModel.currentPushToStartToken else { return }
        let prefix = String(token.prefix(32))
        serverStatusLoading = true
        serverStatusError = nil
        Task {
            do {
                let status = try await NetworkHandler.getDeviceRegistrationStatus(tokenPrefix: prefix)
                serverStatus = status
            } catch {
                serverStatusError = error.localizedDescription
            }
            serverStatusLoading = false
        }
    }

    private func instructionRow(step: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(step).")
                .fontWeight(.bold)
                .frame(width: 20, alignment: .trailing)
            Text(text)
        }
    }
}
