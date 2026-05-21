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
                            Label {
                                Text(sport.capitalized)
                                    .font(.system(.body, design: .rounded))
                            } icon: {
                                Image(systemName: sport.widgetSystemImage)
                                    .foregroundStyle(WatchTokens.sport(sport))
                            }
                        }
                    }
                }

                Section("Favorites") {
                    let favs = Array(viewModel.favoriteTeams).sorted()
                    if favs.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "iphone.gen3")
                                .imageScale(.small)
                                .foregroundStyle(WatchTokens.inkFaint)
                            Text("Add favorites on iPhone")
                                .foregroundStyle(WatchTokens.inkSoft)
                                .font(.system(.caption, design: .rounded))
                        }
                    }
                    ForEach(favs, id: \.self) { team in
                        Text(team)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(WatchTokens.ink)
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
