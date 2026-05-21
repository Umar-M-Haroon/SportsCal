//
//  ModernGameDetailView.swift
//  SportsCal — Design System v1.0 (Phase D.3)
//
//  Game-detail page for the Modern theme. Big quarter-detail strip on
//  top, prominent score with leader emphasis, per-quarter linescore
//  chart, then a Rotator that cycles through last play / leaders /
//  context. Sections with no data fall back to DegradedSectionPlaceholder
//  so the page never silently goes blank.
//
//  Replaces EFRemixGameDetailView in AdaptiveGameDetail's .efRemix branch.
//

import SwiftUI
import SportsCalModel
import NukeUI

struct ModernGameDetailView: View {
    let game: Game
    let homeTeam: Team
    let awayTeam: Team

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites

    /// Owns async loads for the shared `GameDetailSections` stack — standings,
    /// plays. Same pattern Ambient and classic use; reusing the model keeps
    /// loading/error UI consistent across themes.
    @State private var sectionsModel = GameDetailSectionsModel()

    /// User preference for the reel display mode. `true` = auto-rotating
    /// carousel (Rotator); `false` = static segmented picker. Persisted per-
    /// user so the choice carries across game-detail visits.
    @AppStorage("modernGameDetail.autoRotateReel") private var autoRotateReel: Bool = true

    /// Selection for the segmented-picker mode (only consulted when
    /// `autoRotateReel == false`). Defaults to `.play` because that's the
    /// most action-relevant panel during a live game; falls through to
    /// whichever reel is actually available at render time.
    @State private var selectedReel: Reel = .play

    private var sport: SportType { game.sportType ?? .basketball }
    private var accent: Color { Color.app(sport) }

    private var league: Leagues? {
        guard let id = game.idLeague, let intID = Int(id) else { return nil }
        return Leagues(rawValue: intID)
    }

    /// Optional sport type derived strictly from the game's league. Classic
    /// and `GameDetailSections` use this nil-able variant for sport-gating
    /// (injuries / standings / play-by-play). Distinct from `sport` which
    /// has a `.basketball` fallback for theming.
    private var sportType: SportType? {
        guard let league else { return nil }
        return SportType(league: league)
    }

    private var leagueLabel: String {
        if let league {
            return league.leagueName.uppercased()
        }
        return sport.displayName.uppercased()
    }

    private var awayScore: Int? { Int(game.intAwayScore ?? "") }
    private var homeScore: Int? { Int(game.intHomeScore ?? "") }
    private var awayLeader: Bool {
        guard let a = awayScore, let h = homeScore else { return false }
        return a > h
    }
    private var homeLeader: Bool {
        guard let a = awayScore, let h = homeScore else { return false }
        return h > a
    }

    /// Three-way game state. `Game.hasDoneStatus` lumps `"pre"` in with
    /// finished games (its real meaning is "not in progress"), which made
    /// upcoming games render the same as finals — score block at 0-0,
    /// status badge as "FINAL", quarter strip showing "pre" as the period.
    /// This computed property splits them apart properly.
    private enum DetailGameState { case upcoming, live, final }

    private var detailGameState: DetailGameState {
        let s = (game.strStatus ?? "").lowercased()
        let p = (game.strProgress ?? "").lowercased()

        // Pre-game / not started — these are the codes ESPN and TheSportsDB
        // emit for upcoming games. Match before the `hasDoneStatus` fallback,
        // which would otherwise classify them as finished.
        if s == "pre" || s == "ns" || s == "not started" || p == "pre" {
            return .upcoming
        }
        if s == "in" {
            // Stale-status guard: TheSportsDB sometimes leaves `strStatus="in"`
            // for hours after a soccer match ends in a draw (no late winner =
            // no scoreline change to trigger the flip server-side). If kickoff
            // was more than 6h ago, trust the clock over the status flag.
            // 6h covers regulation + extra time + penalties for any sport we
            // care about.
            if let d = game.standardDate, Date().timeIntervalSince(d) > 6 * 60 * 60 {
                return .final
            }
            return .live
        }
        if game.hasDoneStatus { return .final }

        // No status code at all — fall back to the kickoff date.
        if let d = game.standardDate, d > Date() { return .upcoming }
        return .final
    }

    private var isUpcoming: Bool { detailGameState == .upcoming }
    private var isLive: Bool { detailGameState == .live }
    private var isFinal: Bool { detailGameState == .final }

    private var statusEyebrow: String {
        if isFinal { return "FINAL" }
        if isLive {
            if let progress = game.strProgress, !progress.isEmpty {
                return "LIVE · \(progress.uppercased())"
            }
            return "LIVE"
        }
        return "UPCOMING"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .appSpace4) {
                topMeta
                    .padding(.horizontal, .appSpace4)
                    .padding(.top, .appSpace3)

                // For live games, the topMeta row already shows `● LIVE · <period>`
                // via LiveTag — render the quarterStrip only for finals (where it
                // acts as a quiet "FINAL — Q4" badge with no other surface).
                if isFinal {
                    quarterStrip
                        .padding(.horizontal, .appSpace4)
                }

                scoreBlock
                    .padding(.horizontal, .appSpace4)

                if let _ = game.homeLinescores, let _ = game.awayLinescores {
                    linescoreChart
                        .padding(.horizontal, .appSpace4)
                }

                rotatingReel
                    .padding(.horizontal, .appSpace4)

                // Modern-themed parity stack: same data as classic's
                // `GameDetailSections` (playoff series, box score, momentum,
                // key players, play-by-play, injuries, head-to-head,
                // standings) but rendered with Modern design tokens so the
                // visual language stays consistent with the rest of the page.
                ModernGameDetailSections(
                    game: game,
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    league: league,
                    sportType: sportType,
                    model: sectionsModel
                )
                .environment(viewModel)
                .padding(.horizontal, .appSpace4)

                Spacer(minLength: .appSpace5)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        #if !os(macOS)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .toolbar { reelModeToolbarButton }
        .refreshable { await refresh() }
        .task { await initialLoad() }
    }

    /// Toolbar toggle between auto-rotating Rotator and the static segmented
    /// picker. Hidden when there's only one reel available — nothing to switch
    /// between.
    @ToolbarContentBuilder
    private var reelModeToolbarButton: some ToolbarContent {
        if availableReels.count > 1 {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    autoRotateReel.toggle()
                } label: {
                    Image(systemName: autoRotateReel
                          ? "arrow.triangle.2.circlepath"
                          : "rectangle.split.3x1")
                        .accessibilityLabel(Text(autoRotateReel
                                                 ? "Auto-rotating panels — tap to switch to manual"
                                                 : "Manual panel picker — tap to switch to auto-rotate"))
                }
            }
        }
    }

    // MARK: - Async loads (shared sections)

    private var supportsPlayByPlay: Bool {
        switch sportType {
        case .basketball, .nfl, .hockey, .mlb, .soccer: return true
        default: return false
        }
    }

    private var pbpSportPath: String? {
        switch sportType {
        case .basketball: return "basketball"
        case .nfl:        return "football"
        case .hockey:     return "hockey"
        case .mlb:        return "baseball"
        case .soccer:     return "soccer"
        default:          return nil
        }
    }

    private var pbpLeagueSlug: String? {
        switch sportType {
        case .basketball: return "nba"
        case .nfl:        return "nfl"
        case .hockey:     return "nhl"
        case .mlb:        return "mlb"
        case .soccer:     return league?.espnSlug
        default:          return nil
        }
    }

    private func initialLoad() async {
        await sectionsModel.loadStandings(
            leagueID: game.idLeague,
            isIndividualSport: game.isIndividualSport
        )
        if let eventID = game.idEvent, supportsPlayByPlay {
            await sectionsModel.loadPlays(
                eventID: eventID,
                sport: pbpSportPath,
                league: pbpLeagueSlug
            )
        }
    }

    private func refresh() async {
        await initialLoad()
    }

    // MARK: - Top meta line

    private var topMeta: some View {
        HStack(spacing: .appSpace2) {
            Image(systemName: sport.systemImage)
                .imageScale(.small)
                .foregroundStyle(accent)
            Text(leagueLabel).appEyebrow().foregroundStyle(accent)
            Spacer()
            if isLive {
                LiveTag(period: game.strProgress ?? "Live", clock: nil)
            } else {
                Text(statusEyebrow)
                    .appEyebrow()
                    .foregroundStyle(Color.appInkFaint)
            }
            if favorites.contains(game) {
                Image(systemName: "star.fill")
                    .imageScale(.small)
                    .foregroundStyle(Color.appStar)
                    .accessibilityLabel(Text("Favorited"))
            }
        }
    }

    // MARK: - Quarter / period detail strip

    private var quarterStrip: some View {
        let parts = parsedProgress
        return HStack(spacing: .appSpace4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PERIOD").appEyebrow()
                Text(parts.period.isEmpty ? "—" : parts.period)
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundStyle(accent)
            }
            if !parts.clock.isEmpty {
                Divider()
                    .frame(height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TIME").appEyebrow()
                    Text(parts.clock)
                        .font(.system(.title, design: .monospaced).weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(Color.appInk)
                }
            }
            Spacer()
        }
        .padding(.appSpace3)
        .background(
            RoundedRectangle.appShape(.appRadiusMD)
                .fill(Color.appTint(sport))
        )
        .overlay(
            RoundedRectangle.appShape(.appRadiusMD)
                .strokeBorder(accent.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(parts.period.isEmpty ? "Status" : parts.period) \(parts.clock)"))
    }

    /// Parses strProgress like "4Q 4:22" or "73'" or "Top 7" into components.
    private var parsedProgress: (period: String, clock: String) {
        guard let raw = game.strProgress, !raw.isEmpty else { return ("", "") }
        let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2 { return (parts[0], parts[1]) }
        return (raw, "")
    }

    // MARK: - Score block

    private var scoreBlock: some View {
        HStack(alignment: .center, spacing: .appSpace2) {
            teamColumn(team: awayTeam,
                       fallbackName: game.strAwayTeam,
                       score: game.intAwayScore,
                       leader: awayLeader,
                       align: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isUpcoming {
                kickoffCenter
                    .layoutPriority(1)
            }
            teamColumn(team: homeTeam,
                       fallbackName: game.strHomeTeam,
                       score: game.intHomeScore,
                       leader: homeLeader,
                       align: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func teamColumn(
        team: Team,
        fallbackName: String,
        score: String?,
        leader: Bool,
        align: HorizontalAlignment
    ) -> some View {
        VStack(alignment: align, spacing: .appSpace2) {
            teamBadge(team: team, fallbackName: fallbackName)
            Text(team.strTeam ?? fallbackName)
                .font(.appHeadline)
                .lineLimit(1)
                .foregroundStyle(leader ? accent : Color.appInkSoft)
            // Numeric score is meaningful only for live / final games.
            // Upcoming games surface kickoff time in the centered column instead.
            if !isUpcoming {
                Text(score ?? "—")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(leader ? accent : Color.appInk)
            }
        }
    }

    /// Centered kickoff-time chip shown only for upcoming games. Replaces the
    /// 0-0 numeric score that was previously rendered for not-yet-started
    /// games.
    private var kickoffCenter: some View {
        VStack(spacing: 2) {
            Text("KICKOFF").appEyebrow().foregroundStyle(Color.appInkFaint)
            Text(kickoffText ?? "TBD")
                .font(.appTitle)
                .monospacedDigit()
                .foregroundStyle(Color.appInk)
        }
        .padding(.horizontal, .appSpace2)
    }

    private var kickoffText: String? {
        guard let date = game.standardDate else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// 56pt team badge with a tinted-fallback initials chip when the URL is
    /// missing or fails to load. Mirrors classic's `teamBadge` pattern but
    /// styled with Modern tokens (Color.appAlt placeholder, sport-tinted text).
    @ViewBuilder
    private func teamBadge(team: Team, fallbackName: String) -> some View {
        let badgeSize: CGFloat = 56
        if let url = team.strTeamBadge.flatMap({ resolvedBadgeURL($0) }) {
            LazyImage(request: ImageRequest(url: url, processors: [.resize(size: CGSize(width: badgeSize, height: badgeSize))])) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    badgePlaceholder(name: team.strTeamShort ?? team.strTeam ?? fallbackName)
                }
            }
            .frame(width: badgeSize, height: badgeSize)
        } else {
            badgePlaceholder(name: team.strTeamShort ?? team.strTeam ?? fallbackName)
                .frame(width: badgeSize, height: badgeSize)
        }
    }

    private func badgePlaceholder(name: String) -> some View {
        ZStack {
            Circle().fill(Color.appAlt)
            Text(String(name.prefix(3)).uppercased())
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
        }
    }

    /// TheSportsDB serves a smaller "/preview" variant for badges. Match
    /// classic's `resolvedBadgeURL` so the network cache hits stay shared.
    private func resolvedBadgeURL(_ urlString: String) -> URL? {
        if urlString.contains("thesportsdb.com") {
            return URL(string: urlString + "/preview")
        }
        return URL(string: urlString)
    }

    // MARK: - Linescore chart

    private var linescoreChart: some View {
        let away = game.awayLinescores ?? []
        let home = game.homeLinescores ?? []
        let count = max(away.count, home.count)
        let max = ([Double(awayScore ?? 0), Double(homeScore ?? 0)] + away + home).max() ?? 1
        return VStack(alignment: .leading, spacing: .appSpace2) {
            Text("BY \(periodLabel(for: sport)).")
                .appEyebrow()
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<count, id: \.self) { i in
                    let a = i < away.count ? away[i] : 0
                    let h = i < home.count ? home[i] : 0
                    VStack(spacing: 4) {
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(Color.appInkSoft)
                                .frame(height: max > 0 ? CGFloat(a / max) * 60 : 2)
                            Rectangle()
                                .fill(accent)
                                .frame(height: max > 0 ? CGFloat(h / max) * 60 : 2)
                        }
                        Text("\(periodLabel(for: sport))\(i + 1)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.appInkFaint)
                        Text("\(Int(a))–\(Int(h))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.appInkSoft)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 90)
        }
        .appCard()
    }

    private func periodLabel(for sport: SportType) -> String {
        switch sport {
        case .basketball: return "Q"
        case .hockey:     return "P"
        case .mlb:        return "I"
        case .nfl:        return "Q"
        default:          return "P"
        }
    }

    // MARK: - Rotating reel

    private enum Reel: Hashable { case play, leaders, context }
    private var availableReels: [Reel] {
        var r: [Reel] = []
        if let lp = game.lastPlay, !lp.isEmpty { r.append(.play) }
        let leaderCount = (game.homeLeaders?.count ?? 0) + (game.awayLeaders?.count ?? 0)
        if leaderCount > 0 { r.append(.leaders) }
        if hasContext { r.append(.context) }
        return r
    }

    private var hasContext: Bool {
        awayScore != nil || homeScore != nil || (game.venueName?.isEmpty == false)
    }

    @ViewBuilder
    private var rotatingReel: some View {
        let reels = availableReels
        if reels.isEmpty {
            DegradedSectionPlaceholder(
                symbol: "text.bubble",
                message: "Live updates aren't available yet.",
                detail: "Plays, leaders and context will appear once the game is in progress."
            )
        } else if autoRotateReel {
            autoRotatingReel(reels: reels)
        } else {
            staticPickerReel(reels: reels)
        }
    }

    /// Auto-rotating mode (Rotator). Priority-aware: when the game is live,
    /// dwell longer on "Last Play" so live action dominates without locking
    /// out leaders / context. When not live, rotate each panel evenly.
    private func autoRotatingReel(reels: [Reel]) -> some View {
        let pinIndex: Int? = isLive ? reels.firstIndex(of: .play) : nil
        return Rotator(
            items: reels,
            interval: 5.0,
            pinnedIndex: pinIndex,
            pinnedDwellMultiplier: 2.0
        ) { reel in
            panel(for: reel)
        }
        .frame(minHeight: 140, alignment: .topLeading)
    }

    /// Manual mode (segmented picker). The user picks which panel to view;
    /// nothing rotates. Useful when reading is more important than glancing.
    private func staticPickerReel(reels: [Reel]) -> some View {
        let resolvedSelection = reels.contains(selectedReel) ? selectedReel : (reels.first ?? .play)
        return VStack(alignment: .leading, spacing: .appSpace3) {
            Picker("Panel", selection: Binding(
                get: { resolvedSelection },
                set: { selectedReel = $0 }
            )) {
                ForEach(reels, id: \.self) { reel in
                    Text(reelLabel(reel)).tag(reel)
                }
            }
            .pickerStyle(.segmented)

            panel(for: resolvedSelection)
        }
        .frame(minHeight: 140, alignment: .topLeading)
    }

    @ViewBuilder
    private func panel(for reel: Reel) -> some View {
        switch reel {
        case .play:    playPanel
        case .leaders: leadersPanel
        case .context: contextPanel
        }
    }

    private func reelLabel(_ reel: Reel) -> String {
        switch reel {
        case .play:    return "Play"
        case .leaders: return "Leaders"
        case .context: return "Context"
        }
    }

    private var playPanel: some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            Text("LAST PLAY").appEyebrow().foregroundStyle(accent)
            Text(game.lastPlay ?? "")
                .font(.appHeadline)
                .foregroundStyle(Color.appInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appCard()
    }

    private var leadersPanel: some View {
        // ESPN's `competitors[].leaders[]` can contain repeat entries for the same
        // category. Dedup per team by category before concatenating so the 2x2 grid
        // shows distinct categories instead of the same player four times.
        let combined = (game.awayLeaders ?? []).dedupedByCategory()
            + (game.homeLeaders ?? []).dedupedByCategory()
        return VStack(alignment: .leading, spacing: .appSpace2) {
            Text("LEADERS").appEyebrow().foregroundStyle(accent)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: .appSpace2),
                GridItem(.flexible(), spacing: .appSpace2),
            ], spacing: .appSpace2) {
                ForEach(combined.prefix(4), id: \.self) { leader in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leader.categoryDisplay.uppercased())
                            .font(.appCaption)
                            .foregroundStyle(Color.appInkFaint)
                        Text(leader.playerName)
                            .font(.appHeadline)
                            .lineLimit(1)
                        Text(leader.displayValue)
                            .font(.appCaption)
                            .foregroundStyle(accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.appSpace2)
                    .background(
                        RoundedRectangle.appShape(.appRadiusSM)
                            .fill(Color.appAlt)
                    )
                }
            }
        }
        .appCard()
    }

    private var contextPanel: some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            Text("CONTEXT").appEyebrow().foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 6) {
                // Last meeting between these two teams — pulled from the
                // games already in `viewModel.totalGames`. Way more useful
                // than a "Margin" row that's literally just score
                // subtraction. Hidden when there's no prior meeting.
                if let last = lastMeetingDescription {
                    contextRow(label: "Last meeting", value: last)
                }
                if let venue = game.venueName, !venue.isEmpty {
                    contextRow(label: "Venue", value: venue)
                }
                if let homeRecord = game.homeRecord, !homeRecord.isEmpty {
                    contextRow(label: "\(homeTeam.strTeamShort ?? game.strHomeTeam) record", value: homeRecord)
                }
                if let awayRecord = game.awayRecord, !awayRecord.isEmpty {
                    contextRow(label: "\(awayTeam.strTeamShort ?? game.strAwayTeam) record", value: awayRecord)
                }
            }
        }
        .appCard()
    }

    private func contextRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.appCallout).foregroundStyle(Color.appInkSoft)
            Spacer()
            Text(value).font(.appHeadline)
        }
    }

    /// Pulls the most recent completed matchup between these two teams
    /// from the in-memory game cache. Format: `"LAL 110-105 · Mar 12"`
    /// (winner first, score, then the date). Returns `nil` when there's
    /// no prior meeting in the cache so the row drops out.
    private var lastMeetingDescription: String? {
        guard let allGames = viewModel.totalGames else { return nil }
        let cutoff = game.standardDate ?? Date()
        let h = game.strHomeTeam
        let a = game.strAwayTeam
        let prev = allGames
            .filter { $0.id != game.id }
            .filter { ($0.standardDate ?? .distantPast) < cutoff }
            .filter { g in
                (g.strHomeTeam == h && g.strAwayTeam == a) ||
                (g.strHomeTeam == a && g.strAwayTeam == h)
            }
            .filter { $0.intHomeScore != nil && $0.intAwayScore != nil }
            .max { ($0.standardDate ?? .distantPast) < ($1.standardDate ?? .distantPast) }

        guard let prev,
              let hs = Int(prev.intHomeScore ?? ""),
              let as_ = Int(prev.intAwayScore ?? "") else { return nil }

        let dateStr = prev.standardDate?.formatted(.dateTime.month(.abbreviated).day()) ?? ""

        // Draw — common in soccer; just show the score without naming a winner.
        if hs == as_ {
            return "Drew \(hs)-\(as_) · \(dateStr)"
        }

        // Map prev's home/away back to OUR team objects so we can use the
        // short name even if the historic strHomeTeam string differs slightly.
        let prevHomeWon = hs > as_
        let prevHomeWasOurHome = (prev.strHomeTeam == h)
        let winnerName: String
        let winnerScore: Int
        let loserScore: Int
        if prevHomeWon {
            winnerScore = hs
            loserScore = as_
            winnerName = (prevHomeWasOurHome ? homeTeam : awayTeam).strTeamShort
                ?? (prevHomeWasOurHome ? homeTeam : awayTeam).strTeam
                ?? prev.strHomeTeam
        } else {
            winnerScore = as_
            loserScore = hs
            // If prev's home team was OUR home team, then prev's away was OUR away.
            // Otherwise prev's away was OUR home.
            winnerName = (prevHomeWasOurHome ? awayTeam : homeTeam).strTeamShort
                ?? (prevHomeWasOurHome ? awayTeam : homeTeam).strTeam
                ?? prev.strAwayTeam
        }
        return "\(winnerName) \(winnerScore)-\(loserScore) · \(dateStr)"
    }
}

extension Array where Element == GameLeader {
    /// Keeps the first leader seen per `category`. ESPN occasionally returns
    /// duplicate entries for the same category in a single team's payload.
    func dedupedByCategory() -> [GameLeader] {
        var seen: Set<String> = []
        var out: [GameLeader] = []
        for leader in self where seen.insert(leader.category).inserted {
            out.append(leader)
        }
        return out
    }
}
