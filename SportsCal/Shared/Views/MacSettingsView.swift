//
//  MacSettingsView.swift
//  SportsCal
//
//  macOS-only tabbed Settings view for use in a Settings scene.
//

#if os(macOS)
import SwiftUI
import SportsCalModel

struct MacSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            SportsSettingsTab()
                .tabItem { Label("Sports", systemImage: "sportscourt") }
            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 450)
    }
}

// MARK: - Tabs

private struct GeneralSettingsTab: View {
    var body: some View {
        NavigationStack {
            Form {
                ProOptionsSettingsSection()
                ScoresSettingsSection()
                DateFormatSettingsSection()
            }
            .formStyle(.grouped)
        }
    }
}

private struct SportsSettingsTab: View {
    var body: some View {
        NavigationStack {
            Form {
                SoccerCompetitionsSettingsSection()
                BasketballCompetitionsSettingsSection()
                FootballCompetitionsSettingsSection()
                HockeyCompetitionsSettingsSection()
                BaseballCompetitionsSettingsSection()
                GolfCompetitionsSettingsSection()
                TennisCompetitionsSettingsSection()
                RacingCompetitionsSettingsSection()
            }
            .formStyle(.grouped)
        }
    }
}

private struct AdvancedSettingsTab: View {
    var body: some View {
        NavigationStack {
            Form {
                DeveloperSettingsSection()
            }
            .formStyle(.grouped)
        }
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        MacAboutView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
