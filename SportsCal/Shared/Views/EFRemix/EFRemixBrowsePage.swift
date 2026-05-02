//
//  EFRemixBrowsePage.swift
//  SportsCal (iOS)
//
//  EF Remix v2 Browse tab. List of sports with leading sport-colored
//  stripes, mono game counts, optional `BUSY` / `n LIVE` tags. Each row
//  pushes the existing `BrowseSportView` so filtering, "Add to My Sports",
//  etc. continue to work — only the chrome is restyled.
//

import SwiftUI
import SportsCalModel

struct EFRemixBrowsePage: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites
    @Environment(\.colorScheme) private var colorScheme

    private var mode: EFMode { .from(colorScheme) }

    private var sports: [SportType] {
        storage.orderedSports
    }

    /// Total = max(live, fetched-for-sport) so the badge keeps a sane
    /// number even when the live feed is dormant. Mirrors AmbientBrowsePage.
    private func total(for sport: SportType) -> Int {
        let live = viewModel.liveGameCountsBySport[sport] ?? 0
        let fetched = (viewModel.totalGames ?? [])
            .filter { $0.sportType == sport }
            .count
        return max(live, fetched)
    }

    private var totalEvents: Int {
        sports.reduce(0) { $0 + total(for: $1) }
    }

    private var topSport: SportType? {
        sports.max(by: { total(for: $0) < total(for: $1) })
    }

    var body: some View {
        ZStack(alignment: .top) {
            EFTheme.bg(mode).ignoresSafeArea()

            VStack(spacing: 0) {
                EFEyebrowHeadline(
                    eyebrow: "BROWSE · \(totalEvents) EVENTS",
                    headline: "everything,\nat a glance",
                    mode: mode,
                    headlineSize: 30
                )
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sports, id: \.self) { sport in
                            NavigationLink {
                                BrowseSportView(sport: sport)
                                    .environment(viewModel)
                                    .environment(storage)
                                    .environment(favorites)
                            } label: {
                                row(for: sport)
                            }
                            .buttonStyle(.plain)
                        }

                        // Closing dashed line so the last row reads as bracketed.
                        DashedDivider(color: EFTheme.line(mode))
                            .padding(.horizontal, 22)
                    }
                }
            }
        }
        .toolbarBackground(EFTheme.bg(mode), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func row(for sport: SportType) -> some View {
        let liveCount = viewModel.liveGameCountsBySport[sport] ?? 0
        let totalCount = total(for: sport)
        let isTop = topSport == sport && totalCount > 0
        let color = efSportColor(sport, mode: mode)

        return HStack(spacing: 12) {
            EFSportGlyph(sport: sport, size: 18, color: color)

            Text(sport.displayName)
                .font(EFFont.hand(18))
                .foregroundStyle(EFTheme.ink(mode))

            Spacer()

            if liveCount > 0 {
                Text("\(liveCount) LIVE")
                    .font(EFFont.mono(8, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(color)
            } else if isTop {
                Text("BUSY")
                    .font(EFFont.mono(8, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(color)
            }

            Text(String(format: "%02d", totalCount))
                .font(EFFont.mono(22, weight: .bold))
                .foregroundStyle(color)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            DashedDivider(color: EFTheme.line(mode))
                .padding(.horizontal, 22)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
    }
}
