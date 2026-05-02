//
//  EFRemixDayPage.swift
//  SportsCal (iOS)
//
//  Day-tab destination for the EF Remix v2 theme. Auto-picks between the
//  Light Day hero (≤3 live games) and the Heavy B hybrid (≥4 live games).
//  Reads the same view-model data the other day variants use, so date
//  navigation, favorites, and live updates all work the same way.
//

import SwiftUI
import SportsCalModel

struct EFRemixDayPage: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current

    private static let eyebrowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f
    }()

    private var mode: EFMode { .from(colorScheme) }
    private var isToday: Bool { calendar.isDateInToday(selectedDate) }

    private var liveRows: [GameWithTeams] {
        guard isToday else { return [] }
        return viewModel.liveEventsWithTeams
    }

    private var dayRows: [GameWithTeams] {
        viewModel.gamesWithTeams(for: selectedDate)
    }

    private var nonLiveRows: [GameWithTeams] {
        let liveIDs = Set(liveRows.map(\.id))
        return dayRows.filter { !liveIDs.contains($0.id) }
    }

    /// Today's non-live games — upcoming first (by start time ascending), then
    /// finals (by start time descending). Includes finished games so the page
    /// is never empty when "nothing live".
    private var nonLiveSorted: [GameWithTeams] {
        let upcoming = nonLiveRows
            .filter { !$0.game.hasDoneStatus }
            .sorted { ($0.game.standardDate ?? .distantFuture) < ($1.game.standardDate ?? .distantFuture) }
        let finals = nonLiveRows
            .filter { $0.game.hasDoneStatus }
            .sorted { ($0.game.standardDate ?? .distantPast) > ($1.game.standardDate ?? .distantPast) }
        return upcoming + finals
    }

    private var upcomingRows: [GameWithTeams] {
        nonLiveRows
            .filter { !$0.game.hasDoneStatus }
            .sorted { ($0.game.standardDate ?? .distantFuture) < ($1.game.standardDate ?? .distantFuture) }
    }

    private var headlineText: String {
        if isToday {
            switch liveRows.count {
            case 0:
                if dayRows.isEmpty { return "nothing on today" }
                return upcomingRows.isEmpty ? "all wrapped up" : "quiet night"
            case 1: return "1 live"
            case let n where n < 4: return "\(n) live"
            default: return "\(liveRows.count) live, all yours"
            }
        }
        let count = dayRows.count
        if count == 0 {
            return calendar.compare(selectedDate, to: Date(), toGranularity: .day) == .orderedAscending
                ? "no games on tap" : "nothing scheduled"
        }
        let direction = calendar.compare(selectedDate, to: Date(), toGranularity: .day)
        if direction == .orderedAscending {
            return count == 1 ? "1 game · final" : "\(count) games · final"
        }
        return count == 1 ? "1 on tap" : "\(count) on tap"
    }

    private var eyebrowText: String {
        let datePart = Self.eyebrowFormatter.string(from: selectedDate).uppercased()
        if isToday {
            if liveRows.count >= 4 { return "\(datePart) · BUSY DAY" }
            return "\(datePart) · TODAY"
        }
        let direction = calendar.compare(selectedDate, to: Date(), toGranularity: .day)
        if direction == .orderedAscending { return "\(datePart) · PAST" }
        return "\(datePart) · UPCOMING"
    }

    var body: some View {
        ZStack(alignment: .top) {
            EFTheme.bg(mode).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                EFDayChipStrip(
                    selectedDate: $selectedDate,
                    datesWithGames: viewModel.datesWithGames(),
                    mode: mode
                )
                .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if liveRows.count >= 4 {
                            EFHeavyBBody(
                                live: liveRows,
                                other: nonLiveRows,
                                upcoming: upcomingRows,
                                mode: mode
                            )
                        } else {
                            EFLightDayBody(
                                hero: liveRows.first ?? nonLiveSorted.first,
                                isHeroLive: !liveRows.isEmpty,
                                laterTonight: laterTonight,
                                mode: mode
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 40)
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(EFTheme.bg(mode), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    /// In Light mode the hero takes one game; the rest of today's games
    /// list out below it (upcoming first by time, then finals). If the hero
    /// was promoted from `nonLiveSorted` (no live games at all), drop it
    /// from the list to avoid duplication.
    private var laterTonight: [GameWithTeams] {
        if liveRows.isEmpty {
            return Array(nonLiveSorted.dropFirst())
        }
        return nonLiveSorted
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            EFEyebrowHeadline(
                eyebrow: eyebrowText,
                headline: headlineText,
                mode: mode,
                headlineSize: liveRows.count >= 4 ? 24 : 28
            )
            Spacer()
            if !liveRows.isEmpty {
                EFLivePill(count: liveRows.count, mode: mode)
                    .padding(.top, 14)
            }
        }
    }
}

// MARK: - Light Day body

private struct EFLightDayBody: View {
    let hero: GameWithTeams?
    let isHeroLive: Bool
    let laterTonight: [GameWithTeams]
    let mode: EFMode

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let hero {
                NavigationLink {
                    AdaptiveGameDetail(gwt: hero)
                } label: {
                    EFHeroCard(gwt: hero, isLive: isHeroLive, mode: mode)
                        .padding(.horizontal, 18)
                }
                .buttonStyle(.plain)
            } else {
                emptyHero
                    .padding(.horizontal, 22)
            }

            if !laterTonight.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(laterListLabel)
                        .font(EFFont.mono(8, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(EFTheme.faint(mode))
                        .padding(.horizontal, 22)
                        .padding(.bottom, 6)

                    ForEach(laterTonight) { gwt in
                        NavigationLink {
                            AdaptiveGameDetail(gwt: gwt)
                        } label: {
                            EFUpcomingRow(gwt: gwt, mode: mode)
                                .padding(.horizontal, 22)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Section label adapts to mix: pure upcoming → "LATER TONIGHT", any
    /// finished games → "TODAY'S SLATE".
    private var laterListLabel: String {
        let hasFinals = laterTonight.contains { $0.game.hasDoneStatus }
        let hasUpcoming = laterTonight.contains { !$0.game.hasDoneStatus }
        if hasFinals && !hasUpcoming { return "FINAL · \(laterTonight.count)" }
        if hasFinals { return "TODAY'S SLATE · \(laterTonight.count)" }
        return "LATER TONIGHT · \(laterTonight.count)"
    }

    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("nothing on today")
                .font(EFFont.hand(28, relativeTo: .title))
                .foregroundStyle(EFTheme.ink(mode))
            Text("no games scheduled — check Browse for tomorrow's slate.")
                .font(EFFont.hand(14, relativeTo: .body))
                .foregroundStyle(EFTheme.soft(mode))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
    }
}

// MARK: - Hero card

private struct EFHeroCard: View {
    let gwt: GameWithTeams
    let isLive: Bool
    let mode: EFMode
    @Environment(Favorites.self) private var favorites

    private var sport: SportType { gwt.game.sportType ?? .basketball }
    private var color: Color { efSportColor(sport, mode: mode) }
    private var leagueLabel: String {
        if let id = gwt.game.idLeague, let intID = Int(id),
           let league = Leagues(rawValue: intID) {
            return league.leagueName.uppercased()
        }
        return sport.displayName.uppercased()
    }

    private var awayScore: String? { gwt.game.intAwayScore }
    private var homeScore: String? { gwt.game.intHomeScore }
    private var awayInt: Int? { Int(awayScore ?? "") }
    private var homeInt: Int? { Int(homeScore ?? "") }
    private var awayLeader: Bool { (awayInt ?? -1) > (homeInt ?? -1) }
    private var homeLeader: Bool { (homeInt ?? -1) > (awayInt ?? -1) }

    private var isFavorite: Bool { favorites.contains(gwt.game) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text("\(leagueLabel) · \(isLive ? "LIVE" : (gwt.game.hasDoneStatus ? "FINAL" : "SOON"))")
                        .font(EFFont.mono(9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(color)
                }
                Spacer()
                if isFavorite {
                    Text("★ FAV")
                        .font(EFFont.mono(9, weight: .bold))
                        .foregroundStyle(EFTheme.star(mode))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                scoreColumn(label: gwt.game.strAwayTeam, score: awayScore, leader: awayLeader)
                Text("—")
                    .font(EFFont.hand(28))
                    .foregroundStyle(EFTheme.faint(mode))
                scoreColumn(label: gwt.game.strHomeTeam, score: homeScore, leader: homeLeader)
            }

            if isLive, let progress = gwt.game.strProgress, !progress.isEmpty {
                quarterStrip(progress: progress)
            }

            // Rotating context — last play (if any), or fallback to status line.
            let reel = reelItems
            if !reel.isEmpty {
                EFRotator(items: reel, interval: 2.6) { item, _ in
                    HStack(spacing: 8) {
                        Text(item.label)
                            .font(EFFont.mono(8, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(color)
                        Text(item.value)
                            .font(EFFont.hand(13))
                            .foregroundStyle(EFTheme.ink(mode))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 36)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(efSportColor(sport, mode: mode, opacity: mode == .dark ? 0.10 : 0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(efSportColor(sport, mode: mode, opacity: 0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .efCardStripe(color, width: 3, cornerRadius: 14)
        .efFavoriteRing(active: isFavorite, mode: mode, cornerRadius: 14)
    }

    private func scoreColumn(label: String, score: String?, leader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EFFont.hand(12))
                .foregroundStyle(leader ? color : EFTheme.soft(mode))
                .lineLimit(1)
            Text(score ?? "–")
                .font(EFFont.hand(leader ? 64 : 56))
                .monospacedDigit()
                .foregroundStyle(leader ? color : EFTheme.ink(mode))
                .lineLimit(1)
        }
    }

    private func quarterStrip(progress: String) -> some View {
        HStack(spacing: 8) {
            Text(progress.uppercased())
                .font(EFFont.mono(11, weight: .bold))
                .foregroundStyle(color)
            if let last = gwt.game.lastPlay, !last.isEmpty, !sport.isIndividualForUI {
                Text("·")
                    .font(EFFont.mono(9))
                    .foregroundStyle(EFTheme.soft(mode))
                Text(last)
                    .font(EFFont.mono(9))
                    .foregroundStyle(EFTheme.soft(mode))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mode == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Single rotating reel item: a tag and a value. Built from real game
    /// data when possible; falls back to a single static line so the area
    /// doesn't go empty.
    private struct ReelItem: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    private var reelItems: [ReelItem] {
        var items: [ReelItem] = []
        if let last = gwt.game.lastPlay, !last.isEmpty, !sport.isIndividualForUI {
            items.append(ReelItem(label: "LAST PLAY", value: last))
        }
        if let progress = gwt.game.strProgress, !progress.isEmpty, !isLive {
            items.append(ReelItem(label: "STATUS", value: progress))
        }
        if let venue = gwt.game.venueName, !venue.isEmpty {
            items.append(ReelItem(label: "VENUE", value: venue))
        }
        if let date = gwt.game.standardDate, !isLive, !gwt.game.hasDoneStatus {
            let f = DateFormatter()
            f.dateFormat = "EEE · h:mm a"
            items.append(ReelItem(label: "TIPOFF", value: f.string(from: date)))
        }
        return items
    }
}

// MARK: - Upcoming row (Light Day list)

private struct EFUpcomingRow: View {
    let gwt: GameWithTeams
    let mode: EFMode
    @Environment(Favorites.self) private var favorites

    private var sport: SportType { gwt.game.sportType ?? .basketball }
    private var color: Color { efSportColor(sport, mode: mode) }
    private var isFavorite: Bool { favorites.contains(gwt.game) }

    private var leagueLabel: String {
        if let id = gwt.game.idLeague, let intID = Int(id),
           let league = Leagues(rawValue: intID) {
            return league.leagueName
        }
        return sport.displayName
    }

    private var isFinal: Bool { gwt.game.hasDoneStatus }
    private var awayInt: Int? { Int(gwt.game.intAwayScore ?? "") }
    private var homeInt: Int? { Int(gwt.game.intHomeScore ?? "") }

    private var timeText: String {
        guard let date = gwt.game.standardDate else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    var body: some View {
        HStack(spacing: 12) {
            EFSportGlyph(sport: sport, size: 14, color: color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(matchLabel)
                        .font(EFFont.hand(15))
                        .foregroundStyle(EFTheme.ink(mode))
                        .lineLimit(1)
                    if isFavorite {
                        Text("★").foregroundStyle(EFTheme.star(mode))
                    }
                }
                Text(leagueLabel.uppercased())
                    .font(EFFont.mono(9))
                    .tracking(1)
                    .foregroundStyle(EFTheme.soft(mode))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            DashedDivider(color: EFTheme.line(mode))
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isFinal, let a = awayInt, let h = homeInt {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(a)–\(h)")
                    .font(EFFont.mono(13, weight: .bold))
                    .foregroundStyle(EFTheme.ink(mode))
                Text("FINAL")
                    .font(EFFont.mono(8, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(EFTheme.faint(mode))
            }
        } else if isFinal {
            Text("FINAL")
                .font(EFFont.mono(10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(EFTheme.faint(mode))
        } else {
            Text(timeText)
                .font(EFFont.mono(11, weight: .bold))
                .foregroundStyle(color)
        }
    }

    private var matchLabel: String {
        if sport.isIndividualForUI {
            return gwt.game.strHomeTeam
        }
        let away = gwt.awayTeam?.strTeam ?? gwt.game.strAwayTeam
        let home = gwt.homeTeam?.strTeam ?? gwt.game.strHomeTeam
        return "\(away) v \(home)"
    }
}

// MARK: - Heavy B body

private struct EFHeavyBBody: View {
    let live: [GameWithTeams]
    let other: [GameWithTeams]
    let upcoming: [GameWithTeams]
    let mode: EFMode

    @Environment(Favorites.self) private var favorites

    /// Promoted = favorites + leverage tagged. We don't have leverage tags,
    /// so for now: favorites first, else first 3 live games are promoted so
    /// the `★ FOR YOU` section is never empty when there's live action.
    private var promoted: [GameWithTeams] {
        let favs = live.filter { favorites.contains($0.game) }
        if !favs.isEmpty { return favs }
        return Array(live.prefix(3))
    }

    private var rest: [GameWithTeams] {
        let promotedIDs = Set(promoted.map(\.id))
        return live.filter { !promotedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !promoted.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("★ FOR YOU · \(promoted.count)")
                        .font(EFFont.mono(8, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(EFTheme.faint(mode))
                        .padding(.horizontal, 22)

                    VStack(spacing: 8) {
                        ForEach(promoted) { gwt in
                            NavigationLink {
                                AdaptiveGameDetail(gwt: gwt)
                            } label: {
                                EFPromotedRow(gwt: gwt, mode: mode)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }

            if !rest.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ALSO LIVE · \(rest.count)")
                        .font(EFFont.mono(8, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(EFTheme.faint(mode))
                        .padding(.horizontal, 22)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                    ], spacing: 6) {
                        ForEach(rest) { gwt in
                            NavigationLink {
                                AdaptiveGameDetail(gwt: gwt)
                            } label: {
                                EFCompactTile(gwt: gwt, mode: mode)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }

            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LATER TODAY · \(upcoming.count)")
                        .font(EFFont.mono(8, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(EFTheme.faint(mode))
                        .padding(.horizontal, 22)

                    VStack(spacing: 0) {
                        ForEach(upcoming.prefix(6)) { gwt in
                            NavigationLink {
                                AdaptiveGameDetail(gwt: gwt)
                            } label: {
                                EFUpcomingRow(gwt: gwt, mode: mode)
                                    .padding(.horizontal, 22)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Promoted row (Heavy B "FOR YOU")

private struct EFPromotedRow: View {
    let gwt: GameWithTeams
    let mode: EFMode
    @Environment(Favorites.self) private var favorites

    private var sport: SportType { gwt.game.sportType ?? .basketball }
    private var color: Color { efSportColor(sport, mode: mode) }
    private var isFavorite: Bool { favorites.contains(gwt.game) }

    private var awayScore: String { gwt.game.intAwayScore ?? "–" }
    private var homeScore: String { gwt.game.intHomeScore ?? "–" }
    private var awayInt: Int? { Int(gwt.game.intAwayScore ?? "") }
    private var homeInt: Int? { Int(gwt.game.intHomeScore ?? "") }
    private var homeLeader: Bool { (homeInt ?? -1) > (awayInt ?? -1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                EFSportGlyph(sport: sport, size: 11, color: color)
                if let progress = gwt.game.strProgress, !progress.isEmpty {
                    Text("● \(progress)")
                        .font(EFFont.mono(9, weight: .bold))
                        .foregroundStyle(color)
                }
                Spacer()
                if isFavorite {
                    Text("★")
                        .font(EFFont.hand(11))
                        .foregroundStyle(EFTheme.star(mode))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(awayAbbr)
                    .font(EFFont.mono(10))
                    .foregroundStyle(EFTheme.soft(mode))
                    .frame(width: 32, alignment: .leading)
                Text(awayScore)
                    .font(EFFont.hand(22))
                    .monospacedDigit()
                    .foregroundStyle(EFTheme.ink(mode))
                Text("—")
                    .font(EFFont.mono(10))
                    .foregroundStyle(EFTheme.faint(mode))
                Text(homeAbbr)
                    .font(EFFont.mono(10))
                    .foregroundStyle(homeLeader ? color : EFTheme.soft(mode))
                    .frame(width: 32, alignment: .leading)
                Text(homeScore)
                    .font(EFFont.hand(24))
                    .monospacedDigit()
                    .foregroundStyle(homeLeader ? color : EFTheme.ink(mode))
                Spacer(minLength: 0)
            }

            if let last = gwt.game.lastPlay, !last.isEmpty, !sport.isIndividualForUI {
                Text("▸ \(last)")
                    .font(EFFont.hand(11))
                    .foregroundStyle(EFTheme.soft(mode))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(efSportColor(sport, mode: mode, opacity: mode == .dark ? 0.10 : 0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(efSportColor(sport, mode: mode, opacity: 0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .efCardStripe(color, width: 3, cornerRadius: 8)
        .efFavoriteRing(active: isFavorite, mode: mode, cornerRadius: 8)
    }

    private var awayAbbr: String {
        gwt.awayTeam?.strTeamShort ?? abbreviate(gwt.game.strAwayTeam)
    }
    private var homeAbbr: String {
        gwt.homeTeam?.strTeamShort ?? abbreviate(gwt.game.strHomeTeam)
    }
}

// MARK: - Compact tile (Heavy B "ALSO LIVE")

private struct EFCompactTile: View {
    let gwt: GameWithTeams
    let mode: EFMode
    @Environment(Favorites.self) private var favorites

    private var sport: SportType { gwt.game.sportType ?? .basketball }
    private var color: Color { efSportColor(sport, mode: mode) }
    private var isFavorite: Bool { favorites.contains(gwt.game) }

    private var awayInt: Int? { Int(gwt.game.intAwayScore ?? "") }
    private var homeInt: Int? { Int(gwt.game.intHomeScore ?? "") }
    private var homeLeader: Bool { (homeInt ?? -1) > (awayInt ?? -1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                EFSportGlyph(sport: sport, size: 9, color: color)
                Spacer()
                if let progress = gwt.game.strProgress, !progress.isEmpty {
                    Text("● \(progress)")
                        .font(EFFont.mono(8, weight: .bold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
            }
            HStack {
                Text(awayAbbr)
                    .font(EFFont.mono(10))
                    .foregroundStyle(EFTheme.soft(mode))
                Spacer()
                Text(gwt.game.intAwayScore ?? "–")
                    .font(EFFont.mono(14, weight: .bold))
                    .foregroundStyle(EFTheme.ink(mode))
            }
            HStack {
                Text(homeAbbr)
                    .font(EFFont.mono(10))
                    .foregroundStyle(homeLeader ? color : EFTheme.soft(mode))
                Spacer()
                Text(gwt.game.intHomeScore ?? "–")
                    .font(EFFont.mono(14, weight: .bold))
                    .foregroundStyle(homeLeader ? color : EFTheme.ink(mode))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(efSportColor(sport, mode: mode, opacity: mode == .dark ? 0.08 : 0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(efSportColor(sport, mode: mode, opacity: 0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .efCardStripe(color, width: 2, cornerRadius: 6)
        .overlay(alignment: .topTrailing) {
            if isFavorite {
                Text("★")
                    .font(EFFont.hand(10))
                    .foregroundStyle(EFTheme.star(mode))
                    .padding(4)
            }
        }
        .efFavoriteRing(active: isFavorite, mode: mode, cornerRadius: 6)
    }

    private var awayAbbr: String { gwt.awayTeam?.strTeamShort ?? abbreviate(gwt.game.strAwayTeam) }
    private var homeAbbr: String { gwt.homeTeam?.strTeamShort ?? abbreviate(gwt.game.strHomeTeam) }
}

// MARK: - Helpers

/// Top-level abbreviation fallback when team data has no `strTeamShort`.
fileprivate func abbreviate(_ name: String) -> String {
    let cleaned = name.replacingOccurrences(of: ".", with: "")
    let parts = cleaned.split(separator: " ").map(String.init)
    if parts.count >= 2 {
        return parts.suffix(1).joined().uppercased()
    }
    let upper = cleaned.uppercased()
    return String(upper.prefix(3))
}

/// Whether this sport is treated as individual / tournament for layout.
extension SportType {
    /// Convenience that mirrors `Game.isIndividualSport` at the sport-level.
    /// Used to gate "match" labels vs "tournament" labels in EF rows.
    var isIndividualForUI: Bool {
        switch self {
        case .golf, .tennis, .racing: return true
        default: return false
        }
    }
}

// MARK: - Day chip strip

/// Horizontal day picker styled for the EF Remix system. Mono day-of-week
/// caplet over a hand-written day number, dashed sport stripe under days
/// that have games, ink-fill on the selected chip, small ● dot above the
/// number for "today" so the present is easy to spot when scrolled away.
struct EFDayChipStrip: View {
    @Binding var selectedDate: Date
    let datesWithGames: Set<DateComponents>
    let mode: EFMode

    var pastDays: Int = 7
    var futureDays: Int = 14

    private let calendar = Calendar.current

    private static let dayAbbreviationFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private var today: Date { calendar.startOfDay(for: Date()) }

    private var days: [Date] {
        (-pastDays...futureDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }
    }

    @State private var scrollPosition: Date?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.element.timeIntervalSince1970) { index, date in
                    if isNewMonth(date, previousDate: index > 0 ? days[index - 1] : nil) {
                        monthDivider(for: date)
                    }
                    dayChip(for: date)
                        .id(calendar.startOfDay(for: date))
                }
            }
            .padding(.horizontal, 18)
        }
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .onAppear {
            scrollPosition = calendar.startOfDay(for: selectedDate)
        }
        .onChange(of: selectedDate) { _, newValue in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                scrollPosition = calendar.startOfDay(for: newValue)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDate)
    }

    private func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: today)
    }

    private func hasGames(_ date: Date) -> Bool {
        let dc = calendar.dateComponents([.day, .month, .year], from: date)
        return datesWithGames.contains(dc)
    }

    private func isNewMonth(_ date: Date, previousDate: Date?) -> Bool {
        guard let prev = previousDate else { return false }
        return calendar.component(.month, from: date) != calendar.component(.month, from: prev)
    }

    private func monthDivider(for date: Date) -> some View {
        VStack(spacing: 2) {
            Text(Self.monthFormatter.string(from: date).uppercased())
                .font(EFFont.mono(8, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(EFTheme.faint(mode))
            Rectangle()
                .fill(EFTheme.line(mode))
                .frame(width: 1, height: 32)
        }
        .frame(width: 28, height: 56)
    }

    private func dayChip(for date: Date) -> some View {
        let selected = isSelected(date)
        let isPresent = isToday(date)
        let games = hasGames(date)
        let dayNum = "\(calendar.component(.day, from: date))"
        let abbr = Self.dayAbbreviationFormatter.string(from: date).uppercased()

        let textColor: Color = selected ? EFTheme.bg(mode) : EFTheme.ink(mode)
        let metaColor: Color = selected ? EFTheme.bg(mode).opacity(0.78) : EFTheme.faint(mode)

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    if isPresent {
                        Text("●")
                            .font(EFFont.mono(7, weight: .bold))
                            .foregroundStyle(selected ? EFTheme.bg(mode) : EFTheme.live(mode))
                    }
                    Text(abbr)
                        .font(EFFont.mono(9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(metaColor)
                }
                Text(dayNum)
                    .font(EFFont.hand(22))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                Rectangle()
                    .fill(games ? (selected ? EFTheme.bg(mode) : EFTheme.ink(mode)) : Color.clear)
                    .frame(width: 14, height: 2)
            }
            .frame(width: 44, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? EFTheme.ink(mode) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.clear : EFTheme.line(mode), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(date: date, isToday: isPresent, hasGames: games))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func accessibilityLabel(date: Date, isToday: Bool, hasGames: Bool) -> Text {
        let f = DateFormatter()
        f.dateStyle = .full
        var s = f.string(from: date)
        if isToday { s += ", today" }
        s += hasGames ? ", has games" : ", no games"
        return Text(s)
    }
}

// MARK: - Dashed divider

struct DashedDivider: View {
    let color: Color
    var height: CGFloat = 1

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: .init(x: 0, y: size.height / 2))
            path.addLine(to: .init(x: size.width, y: size.height / 2))
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: height, lineCap: .butt, dash: [3, 3]))
        }
        .frame(height: height)
    }
}
