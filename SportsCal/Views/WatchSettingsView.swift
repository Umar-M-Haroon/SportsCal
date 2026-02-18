//
//  WatchSettingsView.swift
//  SportsCalWatch
//
//  Minimal settings: sport toggles and favorites management.
//

import SwiftUI
import SportsCalModel

struct WatchSettingsView: View {
    @Environment(WatchViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Sports") {
                    ForEach(SportType.allCases, id: \.self) { sport in
                        Toggle(isOn: Binding(
                            get: { viewModel.enabledSports.contains(sport) },
                            set: { viewModel.toggleSport(sport, enabled: $0) }
                        )) {
                            Label(sport.capitalized, systemImage: sport.widgetSystemImage)
                                .foregroundStyle(sport.widgetColor)
                        }
                    }
                }

                Section("Favorites") {
                    let favs = Array(viewModel.favoriteTeams).sorted()
                    if favs.isEmpty {
                        Text("Add favorites on iPhone")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    ForEach(favs, id: \.self) { team in
                        Text(team)
                            .font(.system(size: 13))
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.removeFavorite(favs[index])
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
