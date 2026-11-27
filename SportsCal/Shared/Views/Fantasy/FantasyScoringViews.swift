//
//  FantasyScoringViews.swift
//  SportsCal
//
//  Choosing how fantasy points are scored: the presets (free), a custom scoring the
//  user edits, and leagues imported from Sleeper or ESPN (both Pro,
//  `ProFeature.fantasyLeagues`). Sleeper imports go through our server (its player IDs
//  need mapping); ESPN imports run on this device so private-league cookies never
//  leave it.
//

import SwiftUI
import SportsCalModel

// MARK: - Picker

struct FantasyScoringPicker: View {
    let sport: SportType

    @Environment(FantasySettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    @State private var showEditor = false
    @State private var showImport = false
    @State private var detailLeagueID: String?

    private var selection: FantasySettings.Selection { settings.selection(for: sport) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FantasyScoring.presets(for: sport)) { preset in
                        choiceRow(preset.name, subtitle: Self.presetSubtitle(preset),
                                  isSelected: selection == .preset(preset.id)) {
                            choose(.preset(preset.id))
                        }
                    }
                } header: {
                    Text("Presets")
                }

                Section {
                    if settings.hasCustomScoring(for: sport) {
                        choiceRow(settings.customScoring(for: sport)?.name ?? "My scoring",
                                  subtitle: "Your own points per stat",
                                  isSelected: selection == .custom, locked: !settings.isEntitled) {
                            gated { choose(.custom) }
                        }
                    }
                    Button {
                        gated { showEditor = true }
                    } label: {
                        lockedLabel(settings.hasCustomScoring(for: sport) ? "Edit Custom Scoring…" : "Create Custom Scoring…",
                                    systemImage: "slider.horizontal.3")
                    }
                } header: {
                    Text("Custom")
                }

                Section {
                    ForEach(settings.leagues(for: sport)) { league in
                        HStack {
                            choiceRow(league.name,
                                      subtitle: [league.provider.displayName, league.myTeam?.name].compactMap { $0 }.joined(separator: " · "),
                                      isSelected: selection == .league(league.id), locked: !settings.isEntitled) {
                                gated { choose(.league(league.id)) }
                            }
                            Button {
                                detailLeagueID = league.id
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(league.name) settings")
                        }
                    }
                    Button {
                        gated { showImport = true }
                    } label: {
                        lockedLabel("Import League…", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Your leagues")
                } footer: {
                    Text(settings.isEntitled
                         ? "Use your Sleeper or ESPN league's scoring, and see your roster under My Team."
                         : ProFeature.fantasyLeagues.blurb + " Custom scoring and league import need Scoreline Pro.")
                }
            }
            .navigationTitle("Scoring")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showEditor) {
                FantasyCustomScoringEditor(sport: sport) { dismiss() }
            }
            .navigationDestination(isPresented: $showImport) {
                FantasyLeagueImportView(sport: sport) { dismiss() }
            }
            .navigationDestination(item: $detailLeagueID) { id in
                FantasyLeagueDetailView(leagueID: id)
            }
        }
        .sheet(isPresented: $showPaywall) {
            SubscriptionSheet(subscriptionPresented: $showPaywall)
        }
    }

    private func choose(_ selection: FantasySettings.Selection) {
        settings.select(selection, for: sport)
        dismiss()
    }

    /// Runs `action` for Pro users; asks everyone else to subscribe.
    private func gated(_ action: () -> Void) {
        if settings.isEntitled {
            action()
        } else {
            MonetizationTelemetry.gateHit(.fantasyLeagues)
            UpsellCoordinator.shared.requestExplicit(.fantasy) { showPaywall = true }
        }
    }

    private func choiceRow(_ title: String, subtitle: String?, isSelected: Bool, locked: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if locked {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).imageScale(.small)
                } else if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.appAccent).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func lockedLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if !settings.isEntitled {
                Text("PRO")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.appAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.appAccent.opacity(0.14), in: Capsule())
            }
        }
    }

    static func presetSubtitle(_ scoring: FantasyScoring) -> String {
        let perReception = scoring.weights[FantasyStatKey.NFL.receptions] ?? 0
        return perReception == 0 ? "No points per reception" : "\(FantasyScoring.format(perReception)) per reception"
    }
}

// MARK: - Custom editor

struct FantasyCustomScoringEditor: View {
    let sport: SportType
    var finish: () -> Void = {}

    @Environment(FantasySettings.self) private var settings
    @State private var draft: FantasyScoring?

    var body: some View {
        Form {
            if let draft = Binding($draft) {
                Section {
                    TextField("Name", text: draft.name)
                    Menu {
                        ForEach(FantasyScoring.presets(for: sport)) { preset in
                            Button(preset.name) {
                                draft.wrappedValue.weights = preset.weights
                                draft.wrappedValue.rules = preset.rules
                            }
                        }
                    } label: {
                        Label("Start from a preset", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Yards score per yard: 0.04 is a point every 25 yards, 0.1 a point every 10.")
                }

                ForEach(Self.groups(for: sport), id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.keys, id: \.self) { key in
                            weightRow(key, draft: draft)
                        }
                    }
                }

                if !draft.wrappedValue.rules.isEmpty {
                    Section {
                        ForEach(Array(draft.wrappedValue.rules.enumerated()), id: \.offset) { _, rule in
                            LabeledContent(Self.ruleTitle(rule), value: FantasyBreakdownSheet.signed(rule.points))
                        }
                    } header: {
                        Text("Bonuses & tiers")
                    } footer: {
                        Text("These come from the preset you started from.")
                    }
                }
            }
        }
        .navigationTitle("Custom Scoring")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let draft else { return }
                    settings.setCustomScoring(draft)
                    settings.select(.custom, for: sport)
                    finish()
                }
                .disabled(draft?.name.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
            }
        }
        .onAppear {
            if draft == nil { draft = settings.customScoring(for: sport) }
        }
    }

    private func weightRow(_ key: String, draft: Binding<FantasyScoring>) -> some View {
        let weight = Binding<Double>(
            get: { draft.wrappedValue.weights[key] ?? 0 },
            set: { draft.wrappedValue.weights[key] = $0 == 0 ? nil : $0 }
        )
        return HStack {
            Text(FantasyStatKey.label(key))
            Spacer()
            TextField("0", value: weight, format: .number.precision(.fractionLength(0...3)))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 80)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .accessibilityLabel("\(FantasyStatKey.label(key)) points")
        }
    }

    struct Group {
        let title: String
        let keys: [String]
    }

    /// The editable stats by family, in `FantasyStatKey.editable` order.
    static func groups(for sport: SportType) -> [Group] {
        let keys = FantasyStatKey.editable(for: sport)
        let families: [(String, (String) -> Bool)] = [
            ("Passing", { $0.hasPrefix("passing.") }),
            ("Rushing", { $0.hasPrefix("rushing.") }),
            ("Receiving", { $0.hasPrefix("receiving.") }),
            ("Kicking", { $0.hasPrefix("kicking.") }),
            ("Defense / Special Teams", { $0.hasPrefix("dst.") }),
        ]
        var used = Set<String>()
        var out: [Group] = []
        for (title, matches) in families {
            let inFamily = keys.filter(matches)
            used.formUnion(inFamily)
            if !inFamily.isEmpty { out.append(Group(title: title, keys: inFamily)) }
        }
        let rest = keys.filter { !used.contains($0) }
        if !rest.isEmpty { out.insert(Group(title: "Other", keys: rest), at: min(3, out.count)) }
        return out
    }

    static func ruleTitle(_ rule: FantasyScoring.Rule) -> String {
        let label = FantasyStatKey.label(rule.stat)
        if let max = rule.max {
            return "\(label) \(FantasyScoring.format(rule.min))–\(FantasyScoring.format(max - 1))"
        }
        return "\(label) \(FantasyScoring.format(rule.min))+"
    }
}

// MARK: - Import

struct FantasyLeagueImportView: View {
    let sport: SportType
    var finish: () -> Void = {}

    @State private var provider: FantasyLeague.Provider = .sleeper
    @State private var username = ""
    @State private var sleeperUser: FantasySleeperUser?
    @State private var leagueID = ""
    @State private var season = FantasySeason.current()
    @State private var espnS2 = ""
    @State private var swid = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var pending: FantasyLeague?

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $provider) {
                    ForEach(FantasyLeague.Provider.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            switch provider {
            case .sleeper: sleeperSections
            case .espn: espnSections
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.appNegative)
                }
            }
        }
        .navigationTitle("Import League")
        .disabled(isWorking)
        .overlay {
            if isWorking { ProgressView().controlSize(.large) }
        }
        .onChange(of: provider) { _, _ in errorMessage = nil }
        .navigationDestination(item: $pending) { league in
            FantasyLeagueSetupView(league: league, finish: finish)
        }
    }

    // MARK: Sleeper

    @ViewBuilder
    private var sleeperSections: some View {
        Section {
            TextField("Sleeper username", text: $username)
                .textContentType(.username)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit { findSleeperLeagues() }
            Button("Find My Leagues", action: findSleeperLeagues)
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
        } footer: {
            Text("Your username is on your Sleeper profile. Only public league info is read.")
        }

        if let user = sleeperUser {
            Section {
                if user.leagues.isEmpty {
                    Text("No NFL leagues this season.").foregroundStyle(.secondary)
                }
                ForEach(user.leagues) { summary in
                    Button {
                        importSleeper(summary, userID: user.userID)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.name).foregroundStyle(.primary)
                                Text([String(summary.season), summary.teamCount.map { "\($0) teams" }]
                                        .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(user.displayName)'s leagues")
            }
        }
    }

    private func findSleeperLeagues() {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        run {
            sleeperUser = try await NetworkHandler.fetchSleeperUser(username: name)
        } notFound: {
            "No Sleeper user named “\(name)”."
        }
    }

    private func importSleeper(_ summary: FantasyLeagueSummary, userID: String) {
        run {
            pending = try await NetworkHandler.fetchSleeperLeague(leagueID: summary.id, userID: userID)
        } notFound: {
            "Couldn't find that league on Sleeper."
        }
    }

    // MARK: ESPN

    @ViewBuilder
    private var espnSections: some View {
        Section {
            TextField("League ID", text: $leagueID)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Stepper("Season \(String(season))", value: $season, in: 2018...(FantasySeason.current() + 1))
        } footer: {
            Text("The league ID is the number after “leagueId=” in your league's web address on fantasy.espn.com.")
        }

        Section {
            SecureField("espn_s2", text: $espnS2)
                .autocorrectionDisabled()
            TextField("SWID", text: $swid, prompt: Text("SWID ({…})"))
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        } header: {
            Text("Private leagues")
        } footer: {
            Text("Only needed if your league isn't public. Sign in at fantasy.espn.com on a computer, then find the espn_s2 and SWID cookies in your browser's developer tools (Storage or Application → Cookies). They stay on this device and are sent only to ESPN.")
        }

        Section {
            Button("Import League", action: importESPN)
                .disabled(leagueID.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func importESPN() {
        let id = leagueID.trimmingCharacters(in: .whitespaces)
        let s2 = espnS2.trimmingCharacters(in: .whitespacesAndNewlines)
        let swidValue = swid.trimmingCharacters(in: .whitespacesAndNewlines)
        run {
            let league = try await NetworkHandler.fetchESPNFantasyLeague(
                leagueID: id, season: season, espnS2: s2, swid: swidValue)
            if !s2.isEmpty, !swidValue.isEmpty {
                ESPNFantasyCredentials.save(.init(espnS2: s2, swid: swidValue), leagueID: id)
            }
            pending = league
        } notFound: {
            "No ESPN league \(id) for the \(String(season)) season."
        }
    }

    // MARK: Running

    private func run(_ work: @escaping () async throws -> Void, notFound: @escaping () -> String) {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await work()
            } catch NetworkHandler.FantasyError.notFound {
                errorMessage = notFound()
            } catch let error as NetworkHandler.FantasyError {
                errorMessage = error.errorDescription
            } catch is DecodingError {
                errorMessage = "That league came back in a shape we can't read yet."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - New league setup

/// After an import: pick your team, see what scoring couldn't carry over, save.
struct FantasyLeagueSetupView: View {
    let league: FantasyLeague
    var finish: () -> Void = {}

    @Environment(FantasySettings.self) private var settings
    @State private var myTeamID: String?

    var body: some View {
        Form {
            FantasyLeagueInfoSections(league: league, myTeamID: $myTeamID)
        }
        .navigationTitle(league.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var saved = league
                    saved.myTeamID = myTeamID
                    settings.upsert(saved)
                    settings.select(.league(saved.id), for: saved.sport)
                    finish()
                }
            }
        }
        .onAppear { if myTeamID == nil { myTeamID = league.myTeamID } }
    }
}

// MARK: - League detail

struct FantasyLeagueDetailView: View {
    let leagueID: String

    @Environment(FantasySettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var confirmRemove = false

    var body: some View {
        Form {
            if let league = settings.league(id: leagueID) {
                let myTeam = Binding<String?>(
                    get: { settings.league(id: leagueID)?.myTeamID },
                    set: { settings.setMyTeam($0, leagueID: leagueID) }
                )
                FantasyLeagueInfoSections(league: league, myTeamID: myTeam)

                Section {
                    Button {
                        Task { await resync(league) }
                    } label: {
                        HStack {
                            Label("Re-sync League", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isSyncing { ProgressView() }
                        }
                    }
                    .disabled(isSyncing)
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(Color.appNegative)
                    }
                } footer: {
                    Text("Imported from \(league.provider.displayName) \(league.importedAt.formatted(.relative(presentation: .named))). Re-sync after trades and waiver moves.")
                }

                Section {
                    Button("Remove League", role: .destructive) { confirmRemove = true }
                }
                .confirmationDialog("Remove \(league.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) {
                        settings.removeLeague(id: leagueID)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(settings.league(id: leagueID)?.name ?? "League")
    }

    private func resync(_ league: FantasyLeague) async {
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }
        do {
            let fresh: FantasyLeague
            switch league.provider {
            case .sleeper:
                fresh = try await NetworkHandler.fetchSleeperLeague(leagueID: league.providerLeagueID, userID: nil)
            case .espn:
                let credentials = ESPNFantasyCredentials.load(leagueID: league.providerLeagueID)
                fresh = try await NetworkHandler.fetchESPNFantasyLeague(
                    leagueID: league.providerLeagueID, season: league.season,
                    espnS2: credentials?.espnS2, swid: credentials?.swid)
            }
            settings.upsert(fresh)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't re-sync the league."
        }
    }
}

/// My-team picker plus what the import couldn't carry over, shared by setup and detail.
struct FantasyLeagueInfoSections: View {
    let league: FantasyLeague
    @Binding var myTeamID: String?

    var body: some View {
        Section {
            Picker("My team", selection: $myTeamID) {
                Text("None").tag(String?.none)
                ForEach(league.teams) { team in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.name)
                        if let owner = team.ownerName, !owner.isEmpty {
                            Text(owner).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(Optional(team.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("My team")
        } footer: {
            Text("Your team's players show under My Team in the Fantasy hub.")
        }

        if let unmatched = league.teams.first(where: { $0.id == myTeamID })?.unmatched, !unmatched.isEmpty {
            Section {
                ForEach(unmatched, id: \.self) { Text($0) }
            } header: {
                Text("Players we couldn't match")
            } footer: {
                Text("These players won't show live points yet.")
            }
        }

        if !league.unsupportedRules.isEmpty {
            Section {
                ForEach(league.unsupportedRules, id: \.self) { rule in
                    Text(rule).font(.callout.monospaced())
                }
            } header: {
                Text("Scoring rules not applied")
            } footer: {
                Text("Points may differ slightly from \(league.provider.displayName) for players these rules touch.")
            }
        }
    }
}
