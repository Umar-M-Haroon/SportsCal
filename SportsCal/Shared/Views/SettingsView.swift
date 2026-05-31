//
//  SettingsView.swift
//  SettingsView
//
//  Created by Umar Haroon on 8/8/21.
//

import SwiftUI
import SportsCalModel
import RevenueCatUI
import os

// MARK: - Shared Section Views

struct DeveloperSettingsSection: View {
    @Environment(UserDefaultStorage.self) private var appStorage
    @Environment(GameViewModel.self) private var viewModel
    @Environment(SubscriptionManager.self) private var subscriptionManager

    var isTestFlight: Bool {
        guard let path = Bundle.main.appStoreReceiptURL?.path else { return false }
        return path.contains("sandboxReceipt")
    }

    var body: some View {
        @Bindable var bindableAppStorage = appStorage

        Section("Developer") {
            Toggle("Debug Mode", isOn: $bindableAppStorage.debugMode)
            if appStorage.debugMode {
                Picker("Server", selection: $bindableAppStorage.serverEnvironment) {
                    ForEach(ServerEnvironment.allCases, id: \.self) { env in
                        Text(env.displayName).tag(env)
                    }
                }
                .onChange(of: appStorage.serverEnvironment) { _, newValue in
                    NetworkHandler.currentEnvironment = newValue
                    Task { await NetworkHandler.refreshEnvironment() }
                }
                LocalServerStatusView()
                APNsEnvironmentMismatchBanner()
                PushDiagnosticsRow()
                #if DEBUG
                Toggle("Mock Pro Subscription", isOn: Binding(
                    get: { subscriptionManager.isPro },
                    set: { subscriptionManager.setMockPro($0) }
                ))
                #endif
                Button("Dump Caches") {
                    do {
                        try viewModel.dumpCaches()
                    } catch {
                        AppLogger.general.error("Cache dump failed: \(error.localizedDescription)")
                    }
                }
                Toggle("Game count HUD", isOn: $bindableAppStorage.showGameCountHUD)
                NavigationLink("Game count audit") {
                    GameCountAuditView()
                        .environment(viewModel)
                        .environment(appStorage)
                        .navigationTitle("Game count audit")
                }
                NavigationLink("Edge case gallery") {
                    EdgeCaseGalleryView()
                        .navigationTitle("Edge case gallery")
                }
                NavigationLink("iCloud Sync diagnostics") {
                    CloudSyncDiagnosticsView()
                }
                #if os(iOS)
                NavigationLink("Live Activity Testing") {
                    DebugLiveActivityTestView()
                        .environment(viewModel)
                        .environment(appStorage)
                }
                #endif
            }
        }
    }
}

struct ProOptionsSettingsSection: View {
    @Environment(UserDefaultStorage.self) private var appStorage
    @Environment(SubscriptionManager.self) private var subscriptionManager

    var body: some View {
        @Bindable var bindableAppStorage = appStorage

        Section(header: Text("Scoreline Pro Options"), footer: proFooter) {
            HStack {
                Text("Hide events more than ")
                Spacer()
                Menu("\(appStorage.durations.rawValue) away") {
                    Button(Durations.oneDay.rawValue) { appStorage.durations = .oneDay }
                    Button(Durations.oneWeek.rawValue) { appStorage.durations = .oneWeek }
                    Button(Durations.twoWeeks.rawValue) { appStorage.durations = .twoWeeks }
                    Button(Durations.threeWeeks.rawValue) { appStorage.durations = .threeWeeks }
                    Button(Durations.oneMonth.rawValue) { appStorage.durations = .oneMonth }
                    Button(Durations.twoMonths.rawValue) { appStorage.durations = .twoMonths }
                    Button(Durations.sixMonths.rawValue) { appStorage.durations = .sixMonths }
                    Button(Durations.oneYear.rawValue) { appStorage.durations = .oneYear }
                }
            }
            Toggle("Hide past events", isOn: $bindableAppStorage.hidePastEvents)
            Toggle("Show countdown", isOn: $bindableAppStorage.showStartTime)
        }
        .disabled(!subscriptionManager.isPro)
    }

    @ViewBuilder
    private var proFooter: some View {
        if !subscriptionManager.isPro {
            Text("Requires Scoreline Pro")
        }
    }
}

struct ScoresSettingsSection: View {
    @Environment(UserDefaultStorage.self) private var appStorage

    var body: some View {
        Section(header: Text("Scores")) {
            HStack {
                Text("Show past games ")
                Spacer()
                Menu("\(appStorage.hidePastGamesDuration.rawValue) old") {
                    Button(Durations.oneDay.rawValue) { appStorage.hidePastGamesDuration = .oneDay }
                    Button(Durations.oneWeek.rawValue) { appStorage.hidePastGamesDuration = .oneWeek }
                    Button(Durations.twoWeeks.rawValue) { appStorage.hidePastGamesDuration = .twoWeeks }
                    Button(Durations.threeWeeks.rawValue) { appStorage.hidePastGamesDuration = .threeWeeks }
                    Button(Durations.oneMonth.rawValue) { appStorage.hidePastGamesDuration = .oneMonth }
                    Button(Durations.twoMonths.rawValue) { appStorage.hidePastGamesDuration = .twoMonths }
                    Button(Durations.sixMonths.rawValue) { appStorage.hidePastGamesDuration = .sixMonths }
                    Button(Durations.oneYear.rawValue) { appStorage.hidePastGamesDuration = .oneYear }
                }
            }
            .disabled(appStorage.hidePastEvents)
        }
    }
}

struct DateFormatSettingsSection: View {
    @Environment(UserDefaultStorage.self) private var appStorage

    private var datesAndFormats: [(Date, DateFormatter.Style)] {
        let dates = [Date.now, Date.dateAfterDaysFromNow(days: 1), Date.dateAfterDaysFromNow(days: 2), Date.dateAfterDaysFromNow(days: 3)]
        let formats = [DateFormatter.Style.short, .medium, .full, .long]
        return dates.enumerated().map { ($1, formats[$0]) }
    }

    var body: some View {
        @Bindable var bindableAppStorage = appStorage

        Toggle(isOn: $bindableAppStorage.useRelativeValue) {
            Text("Use Relative Time")
        }
        Picker("Date Format", selection: $bindableAppStorage.dateFormat) {
            ForEach(datesAndFormats, id: \.0) { (date, format) in
                Text(format.toExample(date: date))
                    .tag(Int(format.rawValue))
            }
        }
        Section("Preview") {
            ForEach([Date.now, Date.dateAfterDaysFromNow(days: 1), Date.dateAfterDaysFromNow(days: 2), Date.dateAfterDaysFromNow(days: 3)], id: \.self) { date in
                Text(formatFromStorage(date: date, isRelative: appStorage.useRelativeValue))
            }
        }
        .pickerStyle(.inline)
    }

    private func formatFromStorage(date: Date, isRelative: Bool) -> String {
        let formatter = DateFormatters.dateFormatter
        formatter.dateStyle = DateFormatter.Style(rawValue: UInt(appStorage.dateFormat))!
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = isRelative
        return formatter.string(from: date)
    }
}

struct SoccerCompetitionsSettingsSection: View {
    @Environment(UserDefaultStorage.self) private var appStorage

    var body: some View {
        Section {
            #if os(macOS)
            DisclosureGroup("Visible soccer competitions") {
                ForEach(Leagues.allCases.filter({ $0.isSoccer }), id: \.self) { league in
                    CompetitionView(league: league, isShown: !appStorage.hiddenCompetitions.contains(league.leagueName))
                        .environment(appStorage)
                }
            }
            #else
            NavigationLink("Visible soccer competitions") {
                CompetitionPage(competitions: Leagues.allCases.filter({ $0.isSoccer }))
                    .environment(appStorage)
            }
            #endif
        }
    }
}

struct BasketballCompetitionsSettingsSection: View {
    @Environment(UserDefaultStorage.self) private var appStorage

    var body: some View {
        Section {
            #if os(macOS)
            DisclosureGroup("Visible basketball competitions") {
                ForEach(Leagues.allCases.filter({ $0.isBasketball }), id: \.self) { league in
                    CompetitionView(league: league, isShown: !appStorage.hiddenCompetitions.contains(league.leagueName))
                        .environment(appStorage)
                }
            }
            #else
            NavigationLink("Visible basketball competitions") {
                CompetitionPage(competitions: Leagues.allCases.filter({ $0.isBasketball }))
                    .environment(appStorage)
            }
            #endif
        }
    }
}

struct FootballCompetitionsSettingsSection: View {
    @Environment(UserDefaultStorage.self) private var appStorage
    private var leagues: [Leagues] { [.nfl] }

    var body: some View {
        Section {
            #if os(macOS)
            DisclosureGroup("Visible football competitions") {
                ForEach(leagues, id: \.self) { league in
                    CompetitionView(league: league, isShown: !appStorage.hiddenCompetitions.contains(league.leagueName))
                        .environment(appStorage)
                }
            }
            #else
            NavigationLink("Visible football competitions") {
                CompetitionPage(competitions: leagues)
                    .environment(appStorage)
            }
            #endif
        }
    }
}

struct HockeyCompetitionsSettingsSection: View {
    @Environment(UserDefaultStorage.self) private var appStorage
    private var leagues: [Leagues] { [.nhl] }

    var body: some View {
        Section {
            #if os(macOS)
            DisclosureGroup("Visible hockey competitions") {
                ForEach(leagues, id: \.self) { league in
                    CompetitionView(league: league, isShown: !appStorage.hiddenCompetitions.contains(league.leagueName))
                        .environment(appStorage)
                }
            }
            #else
            NavigationLink("Visible hockey competitions") {
                CompetitionPage(competitions: leagues)
                    .environment(appStorage)
            }
            #endif
        }
    }
}

struct BaseballCompetitionsSettingsSection: View {
    @Environment(UserDefaultStorage.self) private var appStorage
    private var leagues: [Leagues] { [.mlb] }

    var body: some View {
        Section {
            #if os(macOS)
            DisclosureGroup("Visible baseball competitions") {
                ForEach(leagues, id: \.self) { league in
                    CompetitionView(league: league, isShown: !appStorage.hiddenCompetitions.contains(league.leagueName))
                        .environment(appStorage)
                }
            }
            #else
            NavigationLink("Visible baseball competitions") {
                CompetitionPage(competitions: leagues)
                    .environment(appStorage)
            }
            #endif
        }
    }
}

struct GolfCompetitionsSettingsSection: View {
    @Environment(UserDefaultStorage.self) private var appStorage
    private var leagues: [Leagues] { Leagues.allCases.filter { $0.isGolf } }

    var body: some View {
        Section {
            #if os(macOS)
            DisclosureGroup("Visible golf competitions") {
                ForEach(leagues, id: \.self) { league in
                    CompetitionView(league: league, isShown: !appStorage.hiddenCompetitions.contains(league.leagueName))
                        .environment(appStorage)
                }
            }
            #else
            NavigationLink("Visible golf competitions") {
                CompetitionPage(competitions: leagues)
                    .environment(appStorage)
            }
            #endif
        }
    }
}

struct TennisCompetitionsSettingsSection: View {
    @Environment(UserDefaultStorage.self) private var appStorage
    private var leagues: [Leagues] { Leagues.allCases.filter { $0.isTennis } }

    var body: some View {
        Section {
            #if os(macOS)
            DisclosureGroup("Visible tennis competitions") {
                ForEach(leagues, id: \.self) { league in
                    CompetitionView(league: league, isShown: !appStorage.hiddenCompetitions.contains(league.leagueName))
                        .environment(appStorage)
                }
            }
            #else
            NavigationLink("Visible tennis competitions") {
                CompetitionPage(competitions: leagues)
                    .environment(appStorage)
            }
            #endif
        }
    }
}

struct RacingCompetitionsSettingsSection: View {
    @Environment(UserDefaultStorage.self) private var appStorage
    private var leagues: [Leagues] { Leagues.allCases.filter { $0.isRacing } }

    var body: some View {
        Section {
            #if os(macOS)
            DisclosureGroup("Visible racing competitions") {
                ForEach(leagues, id: \.self) { league in
                    CompetitionView(league: league, isShown: !appStorage.hiddenCompetitions.contains(league.leagueName))
                        .environment(appStorage)
                }
            }
            #else
            NavigationLink("Visible racing competitions") {
                CompetitionPage(competitions: leagues)
                    .environment(appStorage)
            }
            #endif
        }
    }
}

// MARK: - iOS Settings View

struct SettingsView: View {
    @Environment(UserDefaultStorage.self) private var appStorage
    @Binding var sheetType: SheetType?
    @Environment(GameViewModel.self) private var viewModel
    @State private var showSportPicker: Bool = false
    var isTestFlight: Bool {
        guard let path = Bundle.main.appStoreReceiptURL?.path else {
            return false
        }
        return path.contains("sandboxReceipt")
    }
    var body: some View {
        NavigationStack {
            Form {
                if isTestFlight {
                    Text("You're on a TestFlight build, debug mode is recommended for new features")
                        .font(.headline)
                }
                DeveloperSettingsSection()
                Section(header: Text("Appearance"), footer: Text("Classic is the original design. Ambient is a dark airport-board-style redesign. Modern is the new SF Pro–based system with adaptive sport palette, an adaptive Today screen, and a refreshed Browse and game detail. Switch any time to compare.")) {
                    @Bindable var bindableAppStorage = appStorage
                    Picker("Theme", selection: $bindableAppStorage.appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section(header: Text("Sports"), footer: Text("Choose which sports to show, reorder them, and toggle favorites-only per sport.")) {
                    Button {
                        showSportPicker = true
                    } label: {
                        HStack {
                            Label("Manage Sports", systemImage: "sportscourt")
                            Spacer()
                            Text(enabledSportsSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                NavigationLink("Scoreline Pro") {
                    PaywallView()
                }
                SoccerCompetitionsSettingsSection()
                BasketballCompetitionsSettingsSection()
                ProOptionsSettingsSection()
                #if os(iOS)
                Section(header: Text("Live Activities")) {
                    @Bindable var bindableAppStorage = appStorage
                    Toggle("Auto-follow favorite games", isOn: $bindableAppStorage.autoFollowFavorites)
                    Text("Automatically start Live Activities when your favorite teams play")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                #endif
                Section(header: Text("Personalization")) {
                    @Bindable var bindableAppStorage = appStorage
                    Toggle("Suggested For You", isOn: $bindableAppStorage.showSuggestedForYou)
                    Text("Surface games from teams you've been checking on the Day tab, even if they aren't favorites.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ScoresSettingsSection()
                DateFormatSettingsSection()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        sheetType = nil
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                if isTestFlight {
                    appStorage.debugMode = true
                }
            }
            .sheet(isPresented: $showSportPicker) {
                SportPickerSheet()
                    .environment(appStorage)
                    .environment(viewModel)
            }
        }
    }

    private var enabledSportsSummary: String {
        let enabled = appStorage.enabledSports
        if enabled.isEmpty { return "None" }
        if enabled.count <= 3 { return enabled.map(\.displayName).joined(separator: ", ") }
        return "\(enabled.count) sports"
    }

    func showAttributedString() -> AttributedString {
        var string = AttributedString("Hide events more than")
        //                string.foregroundColor = .blue

        if let range = string.range(of: "1 month") { /// here!
            string[range].foregroundColor = .blue
        }
        return string
    }

    func dateFormats() -> [String: UInt] {
        let formatter = DateFormatters.dateFormatter
        let allCases = [DateFormatter.Style.short, .medium, .full, .long]
        var combos: [String: UInt] = [:]
        for dateStyle in allCases {
            //            for timeStyle in allCases {
            formatter.dateStyle = dateStyle
            formatter.timeStyle = .none
            let string = formatter.string(from: .now)
            combos[string] = dateStyle.rawValue
        }
        return combos
    }
}
//
#Preview {
    @Previewable @State var storage = UserDefaultStorage()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())

    SettingsView(sheetType: Binding<SheetType?>.constant(.settings))
        .environment(storage)
        .environment(viewModel)
}

struct LocalServerStatusView: View {
    @Environment(LocalServerDiscovery.self) private var discovery
    @Environment(UserDefaultStorage.self) private var appStorage
    @State private var manualHost: String = ""
    @State private var resolvedEnv: ServerEnvironment = NetworkHandler.resolvedEnvironment

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text("Local Server:")
                .font(.subheadline)
            Spacer()
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if let host = discovery.discoveredHost {
            HStack {
                Text(host)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        HStack {
            Text("Active: ")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(activeLabel)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        TextField("Manual host override", text: $manualHost)
            .font(.caption.monospaced())
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .onSubmit {
                let trimmed = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
                NetworkHandler.localServerHost = trimmed.isEmpty ? discovery.discoveredHost : trimmed
            }
            .onReceive(NotificationCenter.default.publisher(for: .serverEnvironmentDidChange)) { _ in
                resolvedEnv = NetworkHandler.resolvedEnvironment
            }
            .task {
                // Trigger a fresh probe when the panel appears.
                await NetworkHandler.refreshEnvironment()
                resolvedEnv = NetworkHandler.resolvedEnvironment
            }
    }

    private var activeLabel: String {
        let prefix = appStorage.serverEnvironment == .auto
            ? "Auto → \(resolvedEnv.displayName): "
            : ""
        return prefix + NetworkHandler.baseURL()
    }

    private var statusColor: Color {
        if discovery.discoveredHost != nil { return .green }
        if discovery.isSearching { return .orange }
        return .gray
    }

    private var statusText: String {
        if discovery.discoveredHost != nil { return "Connected" }
        if discovery.isSearching { return "Searching..." }
        return "Not Found"
    }
}

/// Warns when the APNs environment baked into the build can't pair with the
/// currently-selected server: debug builds use sandbox tokens, release builds
/// use production tokens. A mismatch silently drops notifications.
struct APNsEnvironmentMismatchBanner: View {
    @State private var resolved: ServerEnvironment = NetworkHandler.resolvedEnvironment

    private var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private var message: String? {
        if isDebugBuild && resolved == .prod {
            return "Debug build → Prod server: your sandbox APNs token won't pair with prod's production APNs key. Push-to-Start and Live Activities will appear to register, but no pushes will arrive."
        }
        if !isDebugBuild && resolved != .prod {
            return "Release build → \(resolved.displayName): your production APNs token won't pair with the dev server's sandbox APNs key. Push-to-Start and Live Activities will appear to register, but no pushes will arrive."
        }
        return nil
    }

    var body: some View {
        Group {
            if let message {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEnvironmentDidChange)) { _ in
            resolved = NetworkHandler.resolvedEnvironment
        }
    }
}

struct PushDiagnosticsRow: View {
    @State private var diagnostics = PushRegistrationDiagnostics.shared

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Push Diagnostics")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Text("Last registered:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(registeredLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Token:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(diagnostics.lastTokenPrefix.map { "\($0)…" } ?? "—")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Live Activities:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(diagnostics.activeLiveActivities)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let err = diagnostics.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private var registeredLabel: String {
        guard let date = diagnostics.lastRegisteredAt,
              let env = diagnostics.lastEnvironment else { return "Never" }
        return "\(env.displayName) @ \(Self.timestampFormatter.string(from: date))"
    }
}

extension DateFormatter.Style {
    func toExample(date: Date = .now) -> String {
        let formatter = DateFormatters.dateFormatter
        formatter.dateStyle = self
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = false
        let string = formatter.string(from: date)
        return string
    }
    func relativeExample(date: Date = .now) -> String {
        let formatter = DateFormatters.dateFormatter
        formatter.dateStyle = self
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        let string = formatter.string(from: date)
        return string
    }
}
