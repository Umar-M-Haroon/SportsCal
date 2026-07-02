//
//  AmbientBrowsePage.swift
//  SportsCal (iOS)
//
//  Dark airport-board list of sports. Each row pushes the existing
//  `BrowseSportView` so filtering, "Add to My Sports", etc. still work —
//  only the list-style chrome is restyled.
//

import SwiftUI
import SportsCalModel

struct AmbientBrowsePage: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites

    private var sports: [SportType] {
        storage.orderedSports
    }

    private var topSport: SportType? {
        sports.max(by: { total(for: $0) < total(for: $1) })
    }

    var body: some View {
        ZStack(alignment: .top) {
            AmbientPalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                AmbientHeader(
                    eyebrow: "SPORTS",
                    title: "everything, always"
                )
                .padding(.bottom, 10)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        NavigationLink {
                            WorldCupHubView()
                                .environment(viewModel)
                                .environment(storage)
                                .environment(favorites)
                                .preferredColorScheme(.dark)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "soccerball")
                                    .font(.system(size: 16))
                                    .foregroundStyle(AmbientPalette.ink)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("FIFA World Cup 2026")
                                        .font(.ambientDisplay(18, weight: .semibold))
                                        .foregroundStyle(AmbientPalette.ink)
                                    Text("Groups · Bracket · Golden Boot")
                                        .font(.caption)
                                        .foregroundStyle(AmbientPalette.ink.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(AmbientPalette.ink.opacity(0.5))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        if let bracket = viewModel.worldCup?.bracket, !bracket.isEmpty {
                            NavigationLink {
                                WorldCupBracketScreen(bracket: bracket)
                                    .environment(viewModel)
                                    .environment(favorites)
                                    .preferredColorScheme(.dark)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(AmbientPalette.ink)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Knockout Bracket")
                                            .font(.ambientDisplay(18, weight: .semibold))
                                            .foregroundStyle(AmbientPalette.ink)
                                        Text("Round of 32 → Final")
                                            .font(.caption)
                                            .foregroundStyle(AmbientPalette.ink.opacity(0.6))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(AmbientPalette.ink.opacity(0.5))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                        }

                        // Top divider (the departure row draws its divider on the top edge)
                        ForEach(sports, id: \.self) { sport in
                            NavigationLink {
                                BrowseSportView(sport: sport)
                                    .environment(viewModel)
                                    .environment(storage)
                                    .environment(favorites)
                                    .preferredColorScheme(.dark)
                            } label: {
                                sportRow(sport)
                            }
                            .buttonStyle(.plain)
                        }

                        Rectangle()
                            .fill(AmbientPalette.divider)
                            .frame(height: 1)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        #if !os(macOS)
        .toolbarBackground(AmbientPalette.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
    }

    private func sportRow(_ sport: SportType) -> some View {
        let liveCount = viewModel.liveGameCountsBySport[sport] ?? 0
        let totalCount = total(for: sport)
        let isTop = topSport == sport && totalCount > 0

        return HStack(spacing: 12) {
            Image(systemName: sport.systemImage)
                .font(.system(size: 16))
                .foregroundStyle(AmbientPalette.ink)
                .frame(width: 20)

            Text(sport.displayName)
                .font(.ambientDisplay(18, weight: .semibold))
                .foregroundStyle(AmbientPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if liveCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AmbientPalette.live)
                        .frame(width: 5, height: 5)
                    Text("\(liveCount) LIVE")
                        .font(.ambientMono(9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(AmbientPalette.live)
                }
            } else if isTop {
                Text("MOST ACTIVE")
                    .font(.ambientMono(8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(AmbientPalette.highlight)
            }

            Text(String(format: "%02d", totalCount))
                .font(.ambientMono(20, weight: .bold))
                .foregroundStyle(AmbientPalette.ink)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AmbientPalette.divider)
                .frame(height: 1)
        }
    }

    /// Total count = live + currently-visible (fetched) games for that sport.
    /// Uses the same data the Classic BrowsePage badge consumes.
    private func total(for sport: SportType) -> Int {
        let live = viewModel.liveGameCountsBySport[sport] ?? 0
        let fetched = (viewModel.totalGames ?? [])
            .filter { $0.sportType == sport }
            .count
        return max(live, fetched)
    }
}
