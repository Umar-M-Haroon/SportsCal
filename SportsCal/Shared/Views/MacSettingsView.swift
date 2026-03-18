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
        }
        .frame(width: 450)
    }
}

// MARK: - Tabs

private struct GeneralSettingsTab: View {
    var body: some View {
        Form {
            ProOptionsSettingsSection()
            ScoresSettingsSection()
            DateFormatSettingsSection()
        }
        .formStyle(.grouped)
    }
}

private struct SportsSettingsTab: View {
    var body: some View {
        Form {
            SoccerCompetitionsSettingsSection()
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettingsTab: View {
    var body: some View {
        Form {
            DeveloperSettingsSection()
        }
        .formStyle(.grouped)
    }
}
#endif
