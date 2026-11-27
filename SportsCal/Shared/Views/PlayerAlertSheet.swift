//
//  PlayerAlertSheet.swift
//  SportsCal
//
//  The Player Alerts builder: "Notify me when Stephen Curry hits a 3-pointer or
//  reaches 30 points". Opened from a player row in a game's box score or Key
//  Players, a soccer player's page, or Settings → Player & Game Alerts. Saving
//  follows the player and replaces their rules; the free tier is one player with
//  one alert, so going past it opens the paywall (`custom_alert_cap`).
//

import SwiftUI
import SportsCalModel

struct PlayerAlertSheet: View {
    let player: PlayerRef

    @Environment(Favorites.self) private var favorites
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PlayerAlertDraft
    @State private var milestoneStat: String
    @State private var milestoneThreshold: Double
    @State private var showPaywall = false

    private var store: CustomAlertStore { .shared }
    private var isPro: Bool { SubscriptionManager.shared.isPro }

    /// - Parameter threshold: A starting number for the milestone stepper (the Fantasy
    ///   hub's "alert me at 20 points").
    init(player: PlayerRef, threshold: Double? = nil) {
        self.player = player
        var draft = PlayerAlertDraft(player: player, rules: CustomAlertStore.shared.playerRules)
        // Fantasy milestones count with the scoring the user has chosen now.
        if CustomAlertCatalog.offersFantasyMilestones(player.sport) {
            draft.fantasyScoring = FantasySettings.shared.scoring(for: player.sport)
        }
        _draft = State(initialValue: draft)
        let preset = AlertMilestone.presets(for: player.sport).first
        _milestoneStat = State(initialValue: preset?.stat ?? "")
        _milestoneThreshold = State(initialValue: threshold ?? preset?.suggested.first ?? 1)
    }

    private var presets: [AlertMilestone.Preset] { AlertMilestone.presets(for: player.sport) }
    private var selectedPreset: AlertMilestone.Preset? { presets.first { $0.stat == milestoneStat } }
    /// Double- and triple-doubles are reached or not; there's no number to pick.
    private var isYesNoMilestone: Bool {
        milestoneStat == AlertMilestone.doubleDouble || milestoneStat == AlertMilestone.tripleDouble
    }

    private var proposedRules: [AlertRule] { draft.rules(existing: store.playerRules) }
    private var isFollowing: Bool { favorites.isFollowing(athleteID: player.athleteID) }
    private var pausedCount: Int { store.rules(forAthlete: player.athleteID).filter(store.isPaused).count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notify me when \(player.name)…")
                            .font(.headline)
                        Text(CustomAlertCatalog.summary(of: proposedRules, sport: player.sport))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if draft.offersPlays {
                    playsSection
                }
                if draft.offersMilestones, !presets.isEmpty {
                    milestonesSection
                }
                filtersSection

                if pausedCount > 0 {
                    Section {
                        Label("Some of these alerts are paused: the free plan covers one player with one alert.",
                              systemImage: "pause.circle")
                            .font(.footnote)
                        Button("Get Scoreline Pro") { requestPro(kind: .playerPlay) }
                    }
                }

                if isFollowing {
                    Section {
                        Button("Stop Following \(player.name)", role: .destructive) {
                            store.removeRules(forAthlete: player.athleteID)
                            favorites.unfollow(athleteID: player.athleteID)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Player Alerts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showPaywall) {
                SubscriptionSheet(subscriptionPresented: $showPaywall)
            }
        }
    }

    // MARK: Plays

    private var playsSection: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(AlertPlayType.types(for: player.sport), id: \.self) { type in
                    chip(type)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Every time they…")
        } footer: {
            if !isPro {
                Text("Free includes one player with one alert: any mix of plays counts as one. Scoreline Pro is unlimited.")
            }
        }
    }

    private func chip(_ type: AlertPlayType) -> some View {
        let isOn = draft.playTypes.contains(type)
        return Button {
            if isOn { draft.playTypes.remove(type) } else { draft.playTypes.insert(type) }
        } label: {
            HStack(spacing: 4) {
                if isOn { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(type.title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOn ? Color.appAccent.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Color.appAccent : .clear, lineWidth: 1))
            .foregroundStyle(isOn ? Color.appAccent : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Milestones

    private var milestonesSection: some View {
        Section {
            ForEach(draft.milestones, id: \.self) { milestone in
                HStack {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.secondary)
                    Text("Reaches \(milestone.description(sport: player.sport))")
                    Spacer()
                    Button {
                        draft.milestones.removeAll { $0 == milestone }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove")
                }
            }

            Picker("Stat", selection: $milestoneStat) {
                ForEach(presets, id: \.stat) { preset in
                    Text(preset.label.prefix(1).uppercased() + preset.label.dropFirst()).tag(preset.stat)
                }
            }
            .onChange(of: milestoneStat) { _, _ in
                milestoneThreshold = isYesNoMilestone ? 1 : (selectedPreset?.suggested.first ?? 1)
            }

            if !isYesNoMilestone {
                Stepper(value: $milestoneThreshold, in: 1...200, step: 1) {
                    Text("Reaches \(Int(milestoneThreshold)) \(selectedPreset?.label ?? "")")
                        .monospacedDigit()
                }
                if let suggested = selectedPreset?.suggested, suggested.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(suggested, id: \.self) { value in
                            Button(String(Int(value))) { milestoneThreshold = value }
                                .buttonStyle(.bordered)
                                .tint(value == milestoneThreshold ? Color.appAccent : .secondary)
                        }
                    }
                }
            }

            Button {
                draft.addMilestone(AlertMilestone(stat: milestoneStat, threshold: isYesNoMilestone ? 1 : milestoneThreshold))
            } label: {
                Label("Add Milestone", systemImage: "plus.circle")
            }
            .disabled(milestoneStat.isEmpty || draft.milestones.contains(
                AlertMilestone(stat: milestoneStat, threshold: isYesNoMilestone ? 1 : milestoneThreshold)))
        } header: {
            Text("When they reach…")
        } footer: {
            if milestoneStat == AlertMilestone.fantasyPoints, let scoring = draft.fantasyScoring {
                Text("Once per game, the moment they get there. Counted with \(scoring.name) scoring.")
            } else {
                Text("Once per game, the moment they get there.")
            }
        }
    }

    // MARK: Filters

    private var filtersSection: some View {
        Section {
            Toggle(CustomAlertCatalog.finalPeriodLabel(sport: player.sport), isOn: $draft.finalPeriodOnly)
            Toggle(CustomAlertCatalog.closeGameLabel(sport: player.sport), isOn: $draft.closeGameOnly)
        } header: {
            Text("Only when")
        }
    }

    // MARK: Save

    private func save() {
        let rules = proposedRules
        if CustomAlertPolicy.exceedsCap(new: rules, athleteID: player.athleteID,
                                        playerRules: store.playerRules, limits: store.limits) {
            let newKind = rules.first { rule in !store.playerRules.contains { $0.id == rule.id } }?.kind ?? .playerPlay
            requestPro(kind: newKind)
            return
        }
        let existingIDs = Set(store.playerRules.map(\.id))
        for rule in rules where !existingIDs.contains(rule.id) {
            MonetizationTelemetry.customAlertRuleCreated(kind: rule.kind, sport: rule.sport)
        }
        favorites.follow(player)
        store.setRules(rules, forAthlete: player.athleteID)
        if !rules.isEmpty {
            NotificationManager.requestNotificationAccessIfNeeded()
        }
        dismiss()
    }

    private func requestPro(kind: AlertRule.Kind) {
        MonetizationTelemetry.customAlertCapHit(kind: kind)
        MonetizationTelemetry.gateHit(.customAlerts)
        UpsellCoordinator.shared.requestExplicit(.customAlertCap) {
            showPaywall = true
        }
    }
}

// MARK: - Entry points

/// What a player row needs to offer alerts: the player as a `PlayerRef`, or nil when
/// the game's league or the team's ID rules them out.
enum PlayerAlertEntry {
    /// Whether `game`'s league has player alerts (on this platform).
    static func isSupported(_ game: Game) -> Bool {
        guard CustomAlertSupport.isAvailable,
              let league = game.idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:)) else { return false }
        return CustomAlertCatalog.supportsPlayerAlerts(sport: SportType(league: league), league: league)
    }

    /// - Parameters:
    ///   - athleteID: ESPN athlete ID.
    ///   - isHome: The player's side, which picks the game's team ID.
    static func player(athleteID: String, name: String, game: Game, isHome: Bool) -> PlayerRef? {
        guard CustomAlertSupport.isAvailable, !athleteID.isEmpty else { return nil }
        let league = game.idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:))
        guard let league else { return nil }
        let sport = SportType(league: league)
        guard CustomAlertCatalog.supportsPlayerAlerts(sport: sport, league: league) else { return nil }
        let rawID = isHome ? game.idHomeTeam : game.idAwayTeam
        let teamName = isHome ? game.strHomeTeam : game.strAwayTeam
        guard let teamID = (rawID?.isEmpty == false ? rawID : nil) ?? TeamsManager.shared.teamID(forName: teamName),
              teamID.count <= 32 else { return nil }
        return PlayerRef(athleteID: athleteID, name: name, sport: sport, teamID: teamID)
    }
}

enum CustomAlertSupport {
    /// Server-pushed alerts ride the iOS push setup (as soccer match alerts do).
    static var isAvailable: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }
}

/// A small bell beside a followed player's name.
struct PlayerAlertBell: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "bell.fill" : "bell")
            .font(.caption2)
            .foregroundStyle(isOn ? Color.appAccent : Color.secondary.opacity(0.6))
            .accessibilityLabel(isOn ? "Alerts on" : "Set alerts")
    }
}
