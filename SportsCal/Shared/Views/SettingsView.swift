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
                Toggle("Use Local Server", isOn: $bindableAppStorage.useLocalServer)
                    .onChange(of: appStorage.useLocalServer) { _, newValue in
                        NetworkHandler.useLocalServer = newValue
                    }
                LocalServerStatusView()
                Toggle("Mock Pro Subscription", isOn: Binding(
                    get: { subscriptionManager.isPro },
                    set: { subscriptionManager.setMockPro($0) }
                ))
                Button("Dump Caches") {
                    do {
                        try viewModel.dumpCaches()
                    } catch {
                        AppLogger.general.error("Cache dump failed: \(error.localizedDescription)")
                    }
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

// MARK: - iOS Settings View

struct SettingsView: View {
    @Environment(UserDefaultStorage.self) private var appStorage
    @Binding var sheetType: SheetType?
    @Environment(GameViewModel.self) private var viewModel
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
        }
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
            Text(NetworkHandler.baseURL(debug: appStorage.debugMode))
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
