//
//  CustomAlertSettingsView.swift
//  SportsCal
//
//  Settings → Player & Game Alerts: the followed players' alerts (edit or delete)
//  and Game Alerts, a toggle per late-game situation for each sport, covering the
//  user's favorite teams or every game of the league. Game Alerts are Pro: free
//  users see them locked, with a preview of what one looks like.
//

import SwiftUI
import SportsCalModel

/// The Settings row that opens Player & Game Alerts.
struct CustomAlertsSettingsSection: View {
    @Environment(Favorites.self) private var favorites

    var body: some View {
        Section {
            NavigationLink {
                CustomAlertSettingsView()
            } label: {
                HStack {
                    Label("Player & Game Alerts", systemImage: "bell.badge")
                    Spacer()
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            Text("Know the moment your player scores or a game gets tight.")
        }
    }

    private var summary: String {
        let players = favorites.followedPlayers.count
        let situations = CustomAlertStore.shared.situationPrefs.hasAny
        switch (players, situations) {
        case (0, false): return ""
        case (0, true): return "Game alerts on"
        case (1, _): return "1 player"
        default: return "\(players) players"
        }
    }
}

struct CustomAlertSettingsView: View {
    @Environment(Favorites.self) private var favorites

    @State private var editing: PlayerRef?
    @State private var showPaywall = false

    private var store: CustomAlertStore { .shared }
    private var isPro: Bool { SubscriptionManager.shared.isPro }
    private var allowsSituations: Bool { store.limits.allowsSituations }

    var body: some View {
        Form {
            playersSection
            if !allowsSituations {
                lockedPreviewSection
            }
            ForEach(CustomAlertCatalog.situationSports, id: \.self) { sport in
                situationSection(sport)
            }
        }
        .navigationTitle("Player & Game Alerts")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { player in
            PlayerAlertSheet(player: player)
                .environment(favorites)
        }
        .sheet(isPresented: $showPaywall) {
            SubscriptionSheet(subscriptionPresented: $showPaywall)
        }
    }

    // MARK: Player Alerts

    private var playersSection: some View {
        Section {
            if favorites.followedPlayers.isEmpty {
                Text("Tap a player in a game's box score or Key Players to follow them and pick what to hear about.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(favorites.followedPlayers) { player in
                Button {
                    editing = player
                } label: {
                    playerRow(player)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets {
                    let player = favorites.followedPlayers[index]
                    store.removeRules(forAthlete: player.athleteID)
                    favorites.unfollow(athleteID: player.athleteID)
                }
            }
        } header: {
            Text("Player Alerts")
        } footer: {
            if !isPro {
                Text("Free includes one player with one alert. Scoreline Pro covers every player you follow, with as many alerts as you like.")
            }
        }
    }

    private func playerRow(_ player: PlayerRef) -> some View {
        let rules = store.rules(forAthlete: player.athleteID)
        let paused = rules.contains(where: store.isPaused)
        return HStack(spacing: 12) {
            Image(systemName: player.sport.systemImage)
                .foregroundStyle(player.sport.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name).foregroundStyle(.primary)
                Text(rules.isEmpty ? "Following, no alerts" : CustomAlertCatalog.summary(of: rules, sport: player.sport))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if paused {
                Label("Paused", systemImage: "pause.circle")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Paused: over the free limit")
            }
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: Game Alerts

    private var lockedPreviewSection: some View {
        Section {
            CustomAlertPreviewCard(
                title: "Lakers vs Celtics: one-possession game, under 2 minutes",
                detail: "4th Quarter · Celtics 104, Lakers 102"
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            Button {
                requestPro()
            } label: {
                Label("Unlock Game Alerts with Scoreline Pro", systemImage: "lock.open")
            }
        } header: {
            Text("Game Alerts")
        } footer: {
            Text("Get a heads-up when a game gets tight: crunch time, the tying run at the plate, a pulled goalie. No Live Activity needed.")
        }
    }

    private func situationSection(_ sport: SportType) -> some View {
        let prefs = store.situationPrefs
        let league = AlertRule.mainLeague(for: sport)
        let leagueName = league.map { "\($0)".uppercased() } ?? sport.displayName
        return Section {
            if allowsSituations {
                Picker("Games", selection: Binding(
                    get: { prefs.coversAllGames(sport) },
                    set: { store.setCoversAllGames(sport, $0) }
                )) {
                    Text("My Teams").tag(false)
                    Text("All \(leagueName)").tag(true)
                }
                .pickerStyle(.segmented)
            }
            ForEach(CustomAlertCatalog.situations(for: sport), id: \.self) { kind in
                situationToggle(kind, sport: sport, isOn: prefs.isOn(kind, sport: sport))
            }
        } header: {
            Label(sport.displayName, systemImage: sport.systemImage)
        } footer: {
            if allowsSituations, !prefs.coversAllGames(sport), !prefs.enabledKinds(sport: sport).isEmpty {
                Text("For \(leagueName) games your favorite teams play.")
            }
        }
    }

    @ViewBuilder
    private func situationToggle(_ kind: ClutchMoment.Kind, sport: SportType, isOn: Bool) -> some View {
        if allowsSituations {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { on in
                    store.setSituation(kind, sport: sport, on: on)
                    if on {
                        MonetizationTelemetry.customAlertRuleCreated(kind: .gameSituation, sport: sport)
                        NotificationManager.requestNotificationAccessIfNeeded()
                    }
                }
            )) {
                situationLabel(kind)
            }
        } else {
            Button {
                requestPro()
            } label: {
                HStack {
                    situationLabel(kind)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Requires Scoreline Pro")
        }
    }

    private func situationLabel(_ kind: ClutchMoment.Kind) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(CustomAlertCatalog.title(kind))
            Text(CustomAlertCatalog.detail(kind))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func requestPro() {
        MonetizationTelemetry.customAlertCapHit(kind: .gameSituation)
        MonetizationTelemetry.gateHit(.customAlerts)
        UpsellCoordinator.shared.requestExplicit(.customAlertCap) {
            showPaywall = true
        }
    }
}

/// A mock lock-screen banner for the locked Game Alerts preview.
struct CustomAlertPreviewCard: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.footnote)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.appAccent))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("SCORELINE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("now")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example alert: \(title). \(detail)")
    }
}
