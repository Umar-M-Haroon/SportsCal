//
//  ModernBrowsePage.swift
//  SportsCal — Design System v1.0 (Phase D.2)
//
//  Browse tab — list of sports with leading sport-colored stripes,
//  optional BUSY/LIVE tags, mono game counts on the right. Each row
//  pushes the existing BrowseSportView so filtering / "Add to My Sports"
//  / favorites continue to work — only the chrome is restyled.
//
//  Replaces EFRemixBrowsePage under the .efRemix ("Modern") theme.
//  Reads totalGames + liveGameCountsBySport — same data path that's been
//  working all along; this is a pure presentation refresh.
//

import SwiftUI
import SportsCalModel

struct ModernBrowsePage: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites

    private var sports: [SportType] {
        storage.orderedSports
    }

    /// Total = max(live, fetched) so the badge stays sane when the live
    /// feed is dormant. Mirrors EFRemixBrowsePage.
    private func total(for sport: SportType) -> Int {
        let live = viewModel.liveGameCountsBySport[sport] ?? 0
        let fetched = (viewModel.totalGames ?? []).filter { $0.sportType == sport }.count
        return max(live, fetched)
    }

    private func liveCount(for sport: SportType) -> Int {
        viewModel.liveGameCountsBySport[sport] ?? 0
    }

    private var totalEvents: Int {
        sports.reduce(0) { $0 + total(for: $1) }
    }

    /// Tag for the row: nil if quiet, "N LIVE" if live, "BUSY" if a lot
    /// scheduled but none live. Keeps the eye drawn to where the action is.
    private func tag(for sport: SportType) -> String? {
        let live = liveCount(for: sport)
        if live > 0 { return "\(live) LIVE" }
        if total(for: sport) >= 10 { return "BUSY" }
        return nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, .appSpace4)
                    .padding(.top, .appSpace3)
                    .padding(.bottom, .appSpace3)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        NavigationLink {
                            WorldCupHubView()
                                .environment(viewModel)
                                .environment(storage)
                                .environment(favorites)
                        } label: {
                            worldCupRow
                        }
                        .buttonStyle(.plain)

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
                    }
                    .padding(.bottom, .appSpace5)
                }
            }
        }
        #if !os(macOS)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BROWSE · \(totalEvents) EVENTS")
                .appEyebrow()
            Text("everything,\nat a glance")
                .font(.appDisplay)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var worldCupRow: some View {
        let accent = Color.app(.soccer)
        return HStack(spacing: .appSpace3) {
            Image(systemName: "soccerball")
                .imageScale(.medium)
                .foregroundStyle(accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("FIFA World Cup 2026")
                    .font(.appHeadline)
                    .foregroundStyle(Color.appInk)
                Text("Groups · Bracket · Golden Boot")
                    .font(.appCaption)
                    .foregroundStyle(Color.appInkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Color.appInkFaint)
        }
        .padding(.horizontal, .appSpace4)
        .padding(.vertical, .appSpace3)
        .frame(minHeight: .appHit)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, .appSpace2)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.appDivider).frame(height: 1)
        }
    }

    private func row(for sport: SportType) -> some View {
        let count = total(for: sport)
        let live = liveCount(for: sport)
        let accent = Color.app(sport)

        return HStack(spacing: .appSpace3) {
            Image(systemName: sport.systemImage)
                .imageScale(.medium)
                .foregroundStyle(accent)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(sport.displayName)
                .font(.appHeadline)
                .foregroundStyle(Color.appInk)

            Spacer()

            if let tag = tag(for: sport) {
                Text(tag)
                    .font(.appFootnote)
                    .tracking(1.5)
                    .foregroundStyle(accent)
            }

            Text(String(format: "%02d", count))
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(count == 0 ? Color.appInkFaint : accent)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .padding(.horizontal, .appSpace4)
        .padding(.vertical, .appSpace3)
        .frame(minHeight: .appHit)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, .appSpace2)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.appDivider)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel(for: sport, count: count, live: live)))
        .accessibilityAddTraits(.isButton)
    }

    private func accessibilityLabel(for sport: SportType, count: Int, live: Int) -> String {
        var parts = [sport.displayName, "\(count) events"]
        if live > 0 { parts.append("\(live) live") }
        return parts.joined(separator: ", ")
    }
}
