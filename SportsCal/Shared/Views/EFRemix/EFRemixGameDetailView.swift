//
//  EFRemixGameDetailView.swift
//  SportsCal (iOS)
//
//  EF Remix v2 game detail header. Big quarter-detail strip + score, then
//  reuses `GameDetailSections` for the deep data (playoff, box score,
//  momentum chart, key players, play-by-play, injuries, H2H, standings) so
//  we only restyle the chrome.
//
//  Routes for individual sports (golf/tennis tournaments, F1 races) stay
//  on their dedicated `TournamentDetailView` / `RaceDetailView` /
//  `TennisMatchDetailView` paths — `AdaptiveGameDetail` is only invoked
//  for team head-to-head detail, so we can assume team-sport context here.
//

import SwiftUI
import SportsCalModel
import NukeUI
#if os(iOS)
import EventKit
#endif

struct EFRemixGameDetailView: View {
    let game: Game
    let homeTeam: Team
    let awayTeam: Team

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @Environment(\.colorScheme) private var colorScheme
    @State private var sectionsModel = GameDetailSectionsModel()
    @State private var shouldShowSportsCalProAlert = false
    @State private var sheetType: SheetType?

    private var mode: EFMode { .from(colorScheme) }

    private var league: Leagues? {
        guard let id = game.idLeague, let intID = Int(id) else { return nil }
        return Leagues(rawValue: intID)
    }

    private var sportType: SportType? {
        guard let league else { return nil }
        return SportType(league: league)
    }

    private var sport: SportType { sportType ?? .basketball }
    private var color: Color { efSportColor(sport, mode: mode) }

    private var awayInt: Int? { Int(game.intAwayScore ?? "") }
    private var homeInt: Int? { Int(game.intHomeScore ?? "") }
    private var awayLeader: Bool { (awayInt ?? -1) > (homeInt ?? -1) }
    private var homeLeader: Bool { (homeInt ?? -1) > (awayInt ?? -1) }

    private var isLive: Bool {
        !game.hasDoneStatus &&
            (game.intHomeScore != nil || game.intAwayScore != nil ||
             (game.strProgress?.isEmpty == false))
    }

    private var isFinal: Bool { game.hasDoneStatus }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stateBadgeRow
                    .padding(.horizontal, 22)

                playoffBanner
                    .padding(.horizontal, 22)

                // Quarter detail strip — the requested feature.
                quarterStrip
                    .padding(.horizontal, 22)

                scoreRow
                    .padding(.horizontal, 22)

                if !linescoreEntries.isEmpty {
                    quarterBars
                        .padding(.horizontal, 22)
                }

                metaCaplet
                    .padding(.horizontal, 22)

                actionsRow
                    .padding(.horizontal, 18)

                rotatingReel
                    .padding(.horizontal, 22)
                    .padding(.top, 6)

                DashedDivider(color: EFTheme.line(mode))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 6)

                // Re-use the entire classic sections stack below the
                // EF-styled hero so playoff / box score / momentum / etc.
                // are feature-complete without re-implementation.
                GameDetailSections(
                    game: game,
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    league: league,
                    sportType: sportType,
                    model: sectionsModel
                )
                .environment(viewModel)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(EFTheme.bg(mode).ignoresSafeArea())
        .navigationTitle(league?.leagueName ?? "Game")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(EFTheme.bg(mode), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $sheetType) { sheet in
            switch sheet {
            #if os(iOS)
            case .calendar(let eventGame):
                if let game = eventGame {
                    EFCalendarEventSheet(game: game)
                }
            #endif
            default:
                EmptyView()
            }
        }
    }

    // MARK: - State badge

    private var stateBadgeRow: some View {
        HStack {
            Text((league?.leagueName ?? sport.displayName).uppercased() +
                 " · " + game.strAwayTeam.uppercased() +
                 " @ " + game.strHomeTeam.uppercased())
                .font(EFFont.mono(9, weight: .bold))
                .tracking(2)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if isLive {
                HStack(spacing: 4) {
                    Circle().fill(EFTheme.live(mode)).frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(EFFont.mono(10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(EFTheme.live(mode))
                }
            } else if isFinal {
                Text("FINAL")
                    .font(EFFont.mono(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(EFTheme.faint(mode))
            } else {
                Text("UPCOMING")
                    .font(EFFont.mono(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(color)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Quarter strip

    /// Big "QUARTER · TIME LEFT · POSS" card. Only shown when the data
    /// supports it (live game with progress + non-individual sport).
    @ViewBuilder
    private var quarterStrip: some View {
        let progress = game.strProgress ?? ""
        let parsed = parseProgress(progress)

        if isLive, !parsed.period.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(periodLabel)
                        .font(EFFont.mono(8, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(EFTheme.faint(mode))
                    Text(parsed.period)
                        .font(EFFont.hand(36))
                        .foregroundStyle(color)
                }

                Rectangle()
                    .fill(EFTheme.line(mode))
                    .frame(width: 1, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TIME LEFT")
                        .font(EFFont.mono(8, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(EFTheme.faint(mode))
                    Text(parsed.clock.isEmpty ? "—" : parsed.clock)
                        .font(EFFont.mono(28, weight: .bold))
                        .foregroundStyle(EFTheme.ink(mode))
                }

                Spacer()

                if let last = game.lastPlay, !last.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("LAST")
                            .font(EFFont.mono(8, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(EFTheme.faint(mode))
                        Text(last.split(separator: "\n").first.map(String.init) ?? last)
                            .font(EFFont.hand(14))
                            .foregroundStyle(color)
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(efSportColor(sport, mode: mode, opacity: mode == .dark ? 0.10 : 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(efSportColor(sport, mode: mode, opacity: 0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    /// Sport-aware label for the period unit ("QUARTER" / "PERIOD" / "INNING").
    private var periodLabel: String {
        switch sport {
        case .basketball, .nfl: return "QUARTER"
        case .hockey: return "PERIOD"
        case .mlb: return "INNING"
        case .soccer: return "HALF"
        default: return "PERIOD"
        }
    }

    /// Splits a progress string like `"4Q · 4:22"` or `"Q4 4:22"` into
    /// `(period, clock)`. Falls back to dumping everything in `period` if
    /// the format isn't recognized.
    private func parseProgress(_ s: String) -> (period: String, clock: String) {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return ("", "") }
        // Normalize separators
        let cleaned = trimmed
            .replacingOccurrences(of: "·", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        let parts = cleaned.split(separator: " ").map(String.init)
        if parts.count == 1 { return (parts[0], "") }

        // Pick the part that looks like a clock (mm:ss) for the right
        // column; everything else stacks into the period column.
        if let clockIndex = parts.firstIndex(where: { $0.contains(":") }) {
            let clock = parts[clockIndex]
            var periodParts = parts
            periodParts.remove(at: clockIndex)
            return (periodParts.joined(separator: " "), clock)
        }
        return (parts[0], parts.dropFirst().joined(separator: " "))
    }

    // MARK: - Score row

    private var scoreRow: some View {
        HStack(alignment: .top, spacing: 14) {
            scoreColumn(team: awayTeam,
                        fallbackName: game.strAwayTeam,
                        score: awayInt, leader: awayLeader,
                        isFavorite: favorites.teams.contains(game.strAwayTeam))
            VStack {
                Spacer().frame(height: 36)
                Text("—")
                    .font(EFFont.hand(36))
                    .foregroundStyle(EFTheme.faint(mode))
            }
            scoreColumn(team: homeTeam,
                        fallbackName: game.strHomeTeam,
                        score: homeInt, leader: homeLeader,
                        isFavorite: favorites.teams.contains(game.strHomeTeam))
        }
    }

    private func scoreColumn(team: Team, fallbackName: String, score: Int?, leader: Bool, isFavorite: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            EFTeamBadge(urlString: team.strTeamBadge, name: team.strTeamShort ?? team.strTeam, size: 44, mode: mode)

            HStack(spacing: 6) {
                Text(team.strTeam ?? fallbackName)
                    .font(EFFont.hand(13))
                    .foregroundStyle(leader ? color : EFTheme.soft(mode))
                    .lineLimit(1)
                if isFavorite {
                    Text("★")
                        .font(EFFont.hand(11))
                        .foregroundStyle(EFTheme.star(mode))
                }
            }
            Text(score.map(String.init) ?? "–")
                .font(EFFont.hand(leader ? 72 : 60))
                .monospacedDigit()
                .foregroundStyle(leader ? color : EFTheme.ink(mode))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Meta caplet (venue · date · records)

    @ViewBuilder
    private var metaCaplet: some View {
        let parts = metaParts
        if !parts.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { idx, part in
                    Text(part)
                        .font(EFFont.mono(9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(EFTheme.faint(mode))
                    if idx < parts.count - 1 {
                        Text("·")
                            .font(EFFont.mono(9))
                            .foregroundStyle(EFTheme.faint(mode))
                    }
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
        }
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if let venue = game.venueName, !venue.isEmpty {
            parts.append(venue.uppercased())
        }
        if let date = game.standardDate {
            let f = DateFormatter()
            f.dateFormat = (isLive || isFinal) ? "EEE MMM d" : "EEE MMM d · h:mm a"
            parts.append(f.string(from: date).uppercased())
        }
        let awayAbbr = (awayTeam.strTeamShort ?? awayTeam.strTeam ?? game.strAwayTeam).uppercased()
        let homeAbbr = (homeTeam.strTeamShort ?? homeTeam.strTeam ?? game.strHomeTeam).uppercased()
        if let aR = game.awayRecord, !aR.isEmpty,
           let hR = game.homeRecord, !hR.isEmpty {
            parts.append("\(awayAbbr) \(aR) · \(homeAbbr) \(hR)")
        }
        return parts
    }

    // MARK: - Playoff banner

    @ViewBuilder
    private var playoffBanner: some View {
        if let playoff = game.playoff {
            EFPlayoffBanner(playoff: playoff, mode: mode, accent: color,
                            awayAbbr: awayTeam.strTeamShort ?? game.strAwayTeam,
                            homeAbbr: homeTeam.strTeamShort ?? game.strHomeTeam)
        } else if let title = game.fallbackPostseasonTitle {
            HStack(spacing: 8) {
                Text("●")
                    .font(EFFont.mono(8, weight: .bold))
                    .foregroundStyle(EFTheme.star(mode))
                Text("POSTSEASON · \(title.uppercased())")
                    .font(EFFont.mono(9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(EFTheme.star(mode))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(EFTheme.star(mode).opacity(mode == .dark ? 0.10 : 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(EFTheme.star(mode).opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Actions row

    private var actionsRow: some View {
        HStack(spacing: 6) {
            // Favorite — Menu lets user pick which team
            Menu {
                FavoriteMenu(game: game)
                    .environment(favorites)
            } label: {
                EFActionLabel(
                    icon: favorites.contains(game) ? "star.fill" : "star",
                    label: "FAV",
                    active: favorites.contains(game),
                    mode: mode,
                    accent: EFTheme.star(mode)
                )
            }

            #if canImport(ActivityKit) && os(iOS)
            efAutoFollowButton
            #endif

            #if os(iOS)
            Button {
                EKEventStore().requestAccess(to: .event) { _, _ in
                    Task { @MainActor in
                        sheetType = .calendar(game: game)
                    }
                }
            } label: {
                EFActionLabel(icon: "calendar", label: "CAL", active: false, mode: mode, accent: color)
            }
            #endif

            Menu {
                NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                             sheetType: $sheetType,
                             game: game)
            } label: {
                EFActionLabel(icon: "bell.badge", label: "NOTIFY", active: false, mode: mode, accent: color)
            }
        }
        .alert("Scoreline Pro Required", isPresented: $shouldShowSportsCalProAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Subscribe to Pro to schedule game reminders.")
        }
    }

    // MARK: - Quarter bars (per-period stripe)

    private struct LinescoreEntry: Identifiable {
        let id = UUID()
        let label: String
        let away: Double
        let home: Double
        let isCurrent: Bool
    }

    private var linescoreEntries: [LinescoreEntry] {
        let away = game.awayLinescores ?? []
        let home = game.homeLinescores ?? []
        let count = max(away.count, home.count)
        guard count > 0 else { return [] }
        let labels = game.periodLabels(count: count)
        return (0..<count).map { i in
            LinescoreEntry(
                label: i < labels.count ? labels[i] : "\(i + 1)",
                away: i < away.count ? away[i] : 0,
                home: i < home.count ? home[i] : 0,
                isCurrent: isLive && i == count - 1
            )
        }
    }

    private var quarterBars: some View {
        let entries = linescoreEntries
        let maxVal = max(
            entries.flatMap { [$0.away, $0.home] }.max() ?? 1,
            1
        )
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(entries) { e in
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.label + (e.isCurrent ? " ●" : ""))
                        .font(EFFont.mono(8, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(e.isCurrent ? color : EFTheme.faint(mode))
                    Rectangle()
                        .fill(EFTheme.lineHi(mode))
                        .frame(height: max(CGFloat(e.away / maxVal) * 20, 2))
                    Rectangle()
                        .fill(color)
                        .frame(height: max(CGFloat(e.home / maxVal) * 20, 2))
                    Text("\(Int(e.away))–\(Int(e.home))")
                        .font(EFFont.mono(9))
                        .foregroundStyle(EFTheme.soft(mode))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Rotating reel

    /// Top-level rotating area: plays / leaders / context. We hide tabs
    /// where data isn't available so the reel never shows empty state.
    private var reelSections: [ReelSection] {
        let plays = playItems
        let leaders = leaderItems
        let context = contextItems
        var s: [ReelSection] = []
        if !plays.isEmpty { s.append(.init(label: "RECENT PLAYS", kind: .plays(plays))) }
        if !leaders.isEmpty { s.append(.init(label: "LEADERS", kind: .leaders(leaders))) }
        if !context.isEmpty { s.append(.init(label: "CONTEXT", kind: .context(context))) }
        return s
    }

    @ViewBuilder
    private var rotatingReel: some View {
        let sections = reelSections
        if sections.isEmpty {
            EmptyView()
        } else if sections.count == 1 {
            reelContent(for: sections[0])
        } else {
            EFRotator(items: sections, interval: 3.2) { section, _ in
                reelContent(for: section)
            }
            .frame(minHeight: 110, alignment: .top)
        }
    }

    private struct ReelSection: Identifiable {
        let id = UUID()
        let label: String
        let kind: Kind

        enum Kind {
            case plays([PlayItem])
            case leaders([LeaderItem])
            case context([ContextItem])
        }
    }

    private struct PlayItem: Identifiable {
        let id = UUID()
        let text: String
    }

    private struct LeaderItem: Identifiable {
        let id = UUID()
        let label: String
        let who: String
        let value: String
        let isHome: Bool
    }

    private struct ContextItem: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    @ViewBuilder
    private func reelContent(for section: ReelSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.label)
                .font(EFFont.mono(9, weight: .bold))
                .tracking(2)
                .foregroundStyle(color)

            switch section.kind {
            case .plays(let plays):
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plays.prefix(4)) { p in
                        Text("▸ \(p.text)")
                            .font(EFFont.hand(13))
                            .foregroundStyle(EFTheme.ink(mode))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            case .leaders(let leaders):
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ], spacing: 8) {
                    ForEach(leaders.prefix(4)) { l in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.label.uppercased())
                                .font(EFFont.mono(8, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(EFTheme.faint(mode))
                            Text(l.who)
                                .font(EFFont.hand(14))
                                .foregroundStyle(EFTheme.ink(mode))
                                .lineLimit(1)
                            Text(l.value)
                                .font(EFFont.mono(10, weight: .bold))
                                .foregroundStyle(color)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(EFTheme.alt(mode))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(EFTheme.line(mode), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            case .context(let items):
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { c in
                        HStack {
                            Text(c.label)
                                .font(EFFont.hand(13))
                                .foregroundStyle(EFTheme.soft(mode))
                            Spacer()
                            Text(c.value)
                                .font(EFFont.mono(13, weight: .bold))
                                .foregroundStyle(EFTheme.ink(mode))
                        }
                        .overlay(alignment: .bottom) {
                            DashedDivider(color: EFTheme.line(mode))
                                .padding(.top, 22)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playItems: [PlayItem] {
        guard let last = game.lastPlay, !last.isEmpty else { return [] }
        let lines = last.split(separator: "\n").map(String.init)
        return lines.prefix(6).map { PlayItem(text: $0) }
    }

    private var leaderItems: [LeaderItem] {
        var items: [LeaderItem] = []
        if let homeLeaders = game.homeLeaders {
            for l in homeLeaders.prefix(2) {
                items.append(LeaderItem(
                    label: l.categoryDisplay,
                    who: l.playerName,
                    value: l.displayValue,
                    isHome: true
                ))
            }
        }
        if let awayLeaders = game.awayLeaders {
            for l in awayLeaders.prefix(2) {
                items.append(LeaderItem(
                    label: l.categoryDisplay,
                    who: l.playerName,
                    value: l.displayValue,
                    isHome: false
                ))
            }
        }
        return items
    }

    private var contextItems: [ContextItem] {
        var items: [ContextItem] = []
        if let venue = game.venueName, !venue.isEmpty {
            items.append(ContextItem(label: "Venue", value: venue))
        }
        if let progress = game.strProgress, !progress.isEmpty, !isLive {
            items.append(ContextItem(label: "Status", value: progress))
        }
        // Records + venue surface in `metaCaplet` instead — keep the
        // rotating reel focused on context that changes during the game.
        return items
    }

    // MARK: - Auto-follow (EF-styled inline)

    #if canImport(ActivityKit) && os(iOS)
    @ViewBuilder
    private var efAutoFollowButton: some View {
        if shouldShowAutoFollow {
            Button {
                guard let id = game.idEvent else { return }
                if isAutoFollowing {
                    viewModel.appStorage.removeAutoFollow(id)
                } else {
                    viewModel.appStorage.addAutoFollow(id)
                    viewModel.preCacheBadges(homeTeam: homeTeam, awayTeam: awayTeam)
                }
                viewModel.sendAutoFollowRegistration()
            } label: {
                EFActionLabel(
                    icon: isAutoFollowing ? "clock.badge.fill" : "clock.badge",
                    label: isAutoFollowing ? "FOLLOWING" : "FOLLOW",
                    active: isAutoFollowing,
                    mode: mode,
                    accent: color
                )
            }
        }
    }

    private var shouldShowAutoFollow: Bool {
        guard game.idEvent != nil else { return false }
        if game.strStatus == "in" || isFinal { return false }
        return true
    }

    private var isAutoFollowing: Bool {
        guard let id = game.idEvent else { return false }
        return viewModel.appStorage.isAutoFollowing(id)
    }
    #endif
}

// MARK: - EF subviews

/// Team badge styled for EF: rounded-rect tile with subtle background ring,
/// 3-letter mono fallback when the URL fails to load.
struct EFTeamBadge: View {
    let urlString: String?
    let name: String?
    let size: CGFloat
    let mode: EFMode

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(EFTheme.alt(mode))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(EFTheme.line(mode), lineWidth: 1)
                )

            if let urlString, let url = resolved(urlString) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(4)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
    }

    private var fallback: some View {
        Text(name.map { String($0.prefix(3)).uppercased() } ?? "—")
            .font(EFFont.mono(11, weight: .bold))
            .foregroundStyle(EFTheme.soft(mode))
    }

    private func resolved(_ s: String) -> URL? {
        if s.contains("thesportsdb.com") { return URL(string: s + "/preview") }
        return URL(string: s)
    }
}

/// One cell in the EF actions row — bordered tile with a sport-tinted SF
/// icon over a small mono label. Active state inverts the fill.
struct EFActionLabel: View {
    let icon: String
    let label: String
    let active: Bool
    let mode: EFMode
    let accent: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(active ? EFTheme.bg(mode) : accent)
                .frame(height: 18)
            Text(label)
                .font(EFFont.mono(8, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(active ? EFTheme.bg(mode) : EFTheme.soft(mode))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(active ? accent : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(active ? Color.clear : EFTheme.line(mode), lineWidth: 1)
        )
    }
}

/// EF playoff series banner. Shows "GAME n / OF m" + leading-side dots.
struct EFPlayoffBanner: View {
    let playoff: PlayoffContext
    let mode: EFMode
    let accent: Color
    let awayAbbr: String
    let homeAbbr: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("●")
                    .font(EFFont.mono(8, weight: .bold))
                    .foregroundStyle(EFTheme.star(mode))
                Text((playoff.seriesTitle ?? "Postseason").uppercased())
                    .font(EFFont.mono(9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(EFTheme.star(mode))
                Spacer()
                if let bestOf = playoff.bestOf {
                    Text("BEST OF \(bestOf)")
                        .font(EFFont.mono(8, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(EFTheme.soft(mode))
                }
            }

            if let aw = playoff.awayWins, let hw = playoff.homeWins,
               let bestOf = playoff.bestOf {
                seriesDots(awayWins: aw, homeWins: hw, bestOf: bestOf)
                Text(seriesStatus(awayWins: aw, homeWins: hw,
                                  completed: playoff.seriesCompleted ?? false))
                    .font(EFFont.hand(13))
                    .foregroundStyle(EFTheme.soft(mode))
            } else if let gn = playoff.gameNumber {
                Text("GAME \(gn)" + (playoff.bestOf.map { " OF \($0)" } ?? ""))
                    .font(EFFont.mono(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(EFTheme.soft(mode))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(EFTheme.star(mode).opacity(mode == .dark ? 0.10 : 0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(EFTheme.star(mode).opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func seriesDots(awayWins: Int, homeWins: Int, bestOf: Int) -> some View {
        let toClinch = bestOf / 2 + 1
        return HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(awayAbbr.uppercased())
                    .font(EFFont.mono(9, weight: .bold))
                    .foregroundStyle(EFTheme.soft(mode))
                    .frame(width: 28, alignment: .leading)
                ForEach(0..<toClinch, id: \.self) { i in
                    Circle()
                        .fill(i < awayWins ? EFTheme.star(mode) : Color.clear)
                        .overlay(Circle().strokeBorder(EFTheme.lineHi(mode), lineWidth: 1))
                        .frame(width: 8, height: 8)
                }
            }
            HStack(spacing: 4) {
                Text(homeAbbr.uppercased())
                    .font(EFFont.mono(9, weight: .bold))
                    .foregroundStyle(EFTheme.soft(mode))
                    .frame(width: 28, alignment: .leading)
                ForEach(0..<toClinch, id: \.self) { i in
                    Circle()
                        .fill(i < homeWins ? EFTheme.star(mode) : Color.clear)
                        .overlay(Circle().strokeBorder(EFTheme.lineHi(mode), lineWidth: 1))
                        .frame(width: 8, height: 8)
                }
            }
            Spacer()
        }
    }

    private func seriesStatus(awayWins: Int, homeWins: Int, completed: Bool) -> String {
        if awayWins == homeWins { return "series tied · \(awayWins)–\(homeWins)" }
        let leader = awayWins > homeWins ? awayAbbr : homeAbbr
        let lead = abs(awayWins - homeWins)
        if completed { return "\(leader) wins series \(max(awayWins, homeWins))–\(min(awayWins, homeWins))" }
        return "\(leader) leads \(max(awayWins, homeWins))–\(min(awayWins, homeWins))"
    }
}

#if os(iOS)
/// EKEventEditViewController wrapper styled to match the existing
/// `CalendarRepresentable`. We make our own to keep the EF Remix detail
/// view self-contained.
struct EFCalendarEventSheet: View {
    let game: Game

    var body: some View {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let separator = (game.playoff?.isNeutralSite == true) ? " vs " : " @ "
        let _ = configure(event: event, separator: separator)
        return CalendarRepresentable(eventStore: store, event: event)
    }

    @discardableResult
    private func configure(event: EKEvent, separator: String) -> EKEvent {
        event.title = "\(game.strAwayTeam)\(separator)\(game.strHomeTeam)"
        if let date = game.standardDate {
            event.startDate = date
            event.endDate = date.afterHoursFromNow(hours: 2)
        }
        return event
    }
}
#endif
