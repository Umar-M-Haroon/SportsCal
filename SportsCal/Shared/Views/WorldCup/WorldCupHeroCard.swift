//
//  WorldCupHeroCard.swift
//  SportsCal
//
//  The Games-tab World Cup hero: a self-contained mint module that carries the
//  whole tournament — featured match marquee, also-live rows, a fixture ticker
//  for the rest of the matchday, and a horizontal rail of compact group tables.
//  State-aware: leads with the live marquee when matches are in play, the next
//  kickoff when nothing is, and a results recap once the matchday is done.
//  Tapping an "also live" row switches it into the marquee slot.
//

import SwiftUI
import SportsCalModel

// MARK: - World Cup palette

private extension Color {
    /// Soft mint accent — the World Cup's signature color.
    static let wcMint = Color.app(.soccer)
    /// Tinted green hero surface.
    static let wcSurface = Color(light: "#E9F2EB", dark: "#14201B")
    /// Hairline on mint surfaces.
    static let wcLine = Color.app(.soccer).opacity(0.25)
    /// Ink on a solid mint fill (the Following pill).
    static let wcMintInk = Color(light: "#FFFFFF", dark: "#06231A")
}

// MARK: - Match state

private enum WCMatchState { case live, pre, final }

private func wcState(_ game: Game) -> WCMatchState {
    if game.strStatus == "in" { return .live }
    let s = (game.strStatus ?? "").lowercased()
    if s == "pre" || s == "ns" || s == "not started" { return .pre }
    if game.hasDoneStatus { return .final }
    if let d = game.standardDate, d > Date() { return .pre }
    return .final
}

/// Display tricode for a national team: the real short code when present,
/// otherwise initials ("South Korea" → "SKO" beats truncation ambiguity) or a
/// 3-letter prefix for single-word names ("Mexico" → "MEX").
private func wcCode(_ team: Team?, fallback: String) -> String {
    if let short = team?.strTeamShort, !short.isEmpty { return short.uppercased() }
    let name = (team?.strTeam ?? fallback).trimmingCharacters(in: .whitespaces)
    let words = name.split(separator: " ")
    if words.count >= 2 {
        let initials = words.compactMap(\.first)
        if initials.count >= 3 { return String(initials.prefix(3)).uppercased() }
        return (String(words[0].prefix(1)) + String(words[1].prefix(2))).uppercased()
    }
    return String(name.prefix(3)).uppercased()
}

private func wcCountdown(to date: Date?) -> String? {
    guard let date else { return nil }
    let interval = date.timeIntervalSinceNow
    guard interval > 0 else { return nil }
    let hrs = Int(interval) / 3600
    let mins = (Int(interval) % 3600) / 60
    if hrs >= 24 { return "in \(hrs / 24)d \(hrs % 24)h" }
    if hrs > 0 { return "in \(hrs)h \(mins)m" }
    return "in \(mins)m"
}

private func wcKickoff(_ date: Date?) -> String {
    guard let date else { return "TBD" }
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f.string(from: date)
}

// MARK: - Standings loader

/// Fetches the World Cup group tables for the hero rail. Cached statically so
/// the paged day views don't refetch on every swipe.
@MainActor
@Observable
final class WorldCupHeroStandings {
    private(set) var groups: [Child] = []
    private(set) var loading = false

    private static var cache: (groups: [Child], at: Date)?
    private static let staleness: TimeInterval = 15 * 60

    init() {
        // Start from the shared cache so re-instantiated day pages (and
        // previews) show the rail on the first frame, before `loadIfNeeded`.
        if let cached = Self.cache, Date().timeIntervalSince(cached.at) < Self.staleness {
            groups = cached.groups
        }
    }

    #if DEBUG
    /// Seed the static cache so previews render the standings rail without network.
    static func seedForPreviews(groups: [Child]) { cache = (groups, Date()) }
    #endif

    func loadIfNeeded() async {
        if let cached = Self.cache, Date().timeIntervalSince(cached.at) < Self.staleness {
            groups = cached.groups
            return
        }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        guard let standing = try? await NetworkHandler.getStandings(for: String(Leagues.FIFA_World_Cup.rawValue)) else { return }
        let fetched = (standing.standings.children ?? []).filter { ($0.standings?.entries?.isEmpty == false) }
        groups = fetched
        Self.cache = (fetched, Date())
    }
}

// MARK: - Hero card

struct WorldCupHeroCard: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @Environment(UserDefaultStorage.self) private var storage

    @AppStorage("followWorldCup") private var followWorldCup: Bool = false

    @State private var standings = WorldCupHeroStandings()
    /// The match pinned in the marquee slot — tapping an "also live" row
    /// switches it in.
    @State private var featuredID: String?

    private let calendar = Calendar.current

    /// Tournament window — same gate as `WorldCupFeaturedCard`.
    private static let windowStart = DateComponents(calendar: .current, year: 2026, month: 6, day: 11).date ?? .distantFuture
    private static let windowEnd = DateComponents(calendar: .current, year: 2026, month: 7, day: 20).date ?? .distantPast

    /// Whether the hero has anything to show: in the tournament window, or
    /// World Cup matches are in the feed. Day pages use this same check to
    /// keep hero-owned games out of the regular sections.
    static func isActive(viewModel: GameViewModel) -> Bool {
        let now = Date()
        if now >= windowStart && now <= windowEnd { return true }
        return !viewModel.worldCupGamesWithTeams.isEmpty
    }

    // MARK: Data

    private var allMatches: [GameWithTeams] { viewModel.worldCupGamesWithTeams }

    private var todayMatches: [GameWithTeams] {
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return allMatches.filter { gwt in
            guard let d = gwt.game.standardDate else { return false }
            return d >= start && d < end
        }
    }

    private var liveMatches: [GameWithTeams] { todayMatches.filter { wcState($0.game) == .live } }
    private var upcomingToday: [GameWithTeams] { todayMatches.filter { wcState($0.game) == .pre } }
    private var finalsToday: [GameWithTeams] { todayMatches.filter { wcState($0.game) == .final } }

    /// The next kickoff anywhere in the schedule — the marquee lead when
    /// nothing is live today.
    private var nextMatch: GameWithTeams? {
        let now = Date()
        return allMatches.first { wcState($0.game) == .pre && ($0.game.standardDate ?? .distantPast) > now }
    }

    private var marquee: GameWithTeams? {
        if !liveMatches.isEmpty {
            return liveMatches.first { $0.id == featuredID } ?? liveMatches.first
        }
        return nextMatch
    }

    private var alsoLive: [GameWithTeams] {
        guard let marquee, liveMatches.count > 1 else { return [] }
        return liveMatches.filter { $0.id != marquee.id }
    }

    /// The rest of the matchday under the marquee: today's remaining kickoffs,
    /// then today's finals.
    private var ticker: [GameWithTeams] {
        let upcoming = upcomingToday.filter { $0.id != marquee?.id }
        return upcoming + finalsToday
    }

    private var marqueeCaption: (text: String, live: Bool)? {
        if liveMatches.count > 1 { return ("Live now · \(liveMatches.count) matches", true) }
        if liveMatches.count == 1 { return ("Featured · live now", true) }
        if let marquee {
            if let countdown = wcCountdown(to: marquee.game.standardDate) {
                return ("Next match · \(countdown)", false)
            }
            return ("Next match", false)
        }
        if !finalsToday.isEmpty { return ("Matchday complete", false) }
        return nil
    }

    private var tickerCaption: String {
        if upcomingToday.contains(where: { $0.id != marquee?.id }) { return "Later today · group stage" }
        return "Today · results"
    }

    var body: some View {
        if Self.isActive(viewModel: viewModel) {
            VStack(alignment: .leading, spacing: 0) {
                header
                followChip
                    .padding(.horizontal, .appSpace4)
                    .padding(.top, .appSpace2)

                if let caption = marqueeCaption {
                    WCRailCaption(text: caption.text, live: caption.live)
                        .padding(.horizontal, .appSpace4)
                        .padding(.top, .appSpace3)
                }
                if let marquee {
                    marqueeLink(marquee)
                        .padding(.horizontal, .appSpace3)
                        .padding(.top, .appSpace2)
                }

                if !alsoLive.isEmpty {
                    WCRailCaption(text: "Also live · tap to feature", live: true)
                        .padding(.horizontal, .appSpace4)
                        .padding(.top, .appSpace3)
                    VStack(spacing: 0) {
                        ForEach(Array(alsoLive.enumerated()), id: \.element.id) { index, gwt in
                            Button {
                                withAnimation(.snappy(duration: 0.3)) { featuredID = gwt.id }
                            } label: {
                                WCFixtureRow(gameWithTeams: gwt, showDivider: index < alsoLive.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, .appSpace3)
                }

                if !ticker.isEmpty {
                    WCRailCaption(text: tickerCaption)
                        .padding(.horizontal, .appSpace4)
                        .padding(.top, .appSpace3)
                    VStack(spacing: 0) {
                        ForEach(Array(ticker.enumerated()), id: \.element.id) { index, gwt in
                            NavigationLink {
                                detailDestination(for: gwt)
                            } label: {
                                WCFixtureRow(gameWithTeams: gwt, showDivider: index < ticker.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, .appSpace3)
                }

                standingsRail
            }
            .padding(.bottom, .appSpace4)
            .background(RoundedRectangle.appShape(.appRadiusXL).fill(Color.wcSurface))
            .overlay(RoundedRectangle.appShape(.appRadiusXL).stroke(Color.wcLine, lineWidth: 1))
            .task { await standings.loadIfNeeded() }
        }
    }

    // MARK: Header

    private var header: some View {
        NavigationLink {
            WorldCupHubView()
                .environment(viewModel)
                .environment(favorites)
                .environment(storage)
        } label: {
            HStack(spacing: .appSpace3) {
                ZStack {
                    Circle().fill(Color.wcMint.opacity(0.16)).frame(width: 42, height: 42)
                    Image(systemName: "soccerball")
                        .font(.title3)
                        .foregroundStyle(Color.wcMint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("FIFA World Cup 2026")
                        .font(.appHeadline)
                        .foregroundStyle(Color.appInk)
                    Text("Jun 11 – Jul 19 · USA · CAN · MEX")
                        .font(.appCaption)
                        .foregroundStyle(Color.appInkSoft)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(Color.appInkFaint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, .appSpace4)
        .padding(.top, .appSpace4)
    }

    /// Compact mint follow pill — a confirmation chip when following, an
    /// outlined CTA when not.
    private var followChip: some View {
        Button {
            followWorldCup.toggle()
            if followWorldCup {
                #if os(iOS)
                viewModel.reconcileWorldCupFollows()
                #endif
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: followWorldCup ? "bell.fill" : "bell")
                    .font(.caption2)
                Text(followWorldCup ? "Following" : "Follow World Cup")
                    .font(.appFootnote)
                    .tracking(0.5)
            }
            .padding(.horizontal, .appSpace3)
            .padding(.vertical, .appSpace2)
            .background(Capsule().fill(followWorldCup ? Color.wcMint : .clear))
            .overlay(Capsule().stroke(Color.wcMint, lineWidth: followWorldCup ? 0 : 1.5))
            .foregroundStyle(followWorldCup ? Color.wcMintInk : Color.wcMint)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Marquee

    private func marqueeLink(_ gwt: GameWithTeams) -> some View {
        NavigationLink {
            detailDestination(for: gwt)
        } label: {
            WCMarqueeCard(gameWithTeams: gwt)
        }
        .buttonStyle(.plain)
        .id(gwt.id)
    }

    @ViewBuilder
    private func detailDestination(for gwt: GameWithTeams) -> some View {
        AdaptiveGameDetail(
            game: gwt.game,
            homeTeam: gwt.homeTeam ?? Team(strTeam: gwt.game.strHomeTeam),
            awayTeam: gwt.awayTeam ?? Team(strTeam: gwt.game.strAwayTeam)
        )
    }

    // MARK: Standings rail

    @ViewBuilder
    private var standingsRail: some View {
        if !standings.groups.isEmpty {
            WCRailCaption(text: "Group stage · standings")
                .padding(.horizontal, .appSpace4)
                .padding(.top, .appSpace3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .appSpace3) {
                    ForEach(Array(standings.groups.enumerated()), id: \.offset) { _, group in
                        WCGroupCard(group: group)
                    }
                }
                .padding(.horizontal, .appSpace4)
            }
            .padding(.top, .appSpace2)
        } else if standings.loading && todayMatches.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.top, .appSpace3)
        }
    }
}

// MARK: - Rail caption

/// Thin mono eyebrow inside the hero surface. Live captions go red with a
/// pulsing dot.
private struct WCRailCaption: View {
    let text: String
    var live: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            if live { WCLiveDot(size: 6) }
            Text(text)
                .font(.appFootnote)
                .tracking(1.8)
                .textCase(.uppercase)
        }
        .foregroundStyle(live ? Color.appLive : Color.appInkFaint)
    }
}

private struct WCLiveDot: View {
    var size: CGFloat = 7
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.appLive.opacity(0.5))
                .scaleEffect(pulsing ? 2.2 : 0.9)
                .opacity(pulsing ? 0 : 0.6)
            Circle().fill(Color.appLive)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Marquee card

/// The featured-match card: flags and tricodes on the wings, asymmetric score
/// weights toward the leader, the live clock (or kickoff + countdown) in the
/// center, and the last play underneath.
private struct WCMarqueeCard: View {
    let gameWithTeams: GameWithTeams

    private var game: Game { gameWithTeams.game }
    private var state: WCMatchState { wcState(game) }
    private var hasScore: Bool { state != .pre }
    private var awayScore: Int { Int(game.intAwayScore ?? "") ?? 0 }
    private var homeScore: Int { Int(game.intHomeScore ?? "") ?? 0 }

    var body: some View {
        VStack(spacing: .appSpace3) {
            HStack(alignment: .top, spacing: .appSpace2) {
                side(
                    code: wcCode(gameWithTeams.awayTeam, fallback: game.strAwayTeam),
                    badge: game.strAwayTeamBadge,
                    score: hasScore ? awayScore : nil,
                    winning: hasScore && awayScore > homeScore,
                    isHome: false
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                center
                    .padding(.top, .appSpace2)
                side(
                    code: wcCode(gameWithTeams.homeTeam, fallback: game.strHomeTeam),
                    badge: game.strHomeTeamBadge,
                    score: hasScore ? homeScore : nil,
                    winning: hasScore && homeScore > awayScore,
                    isHome: true
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if state != .pre, let play = game.lastPlay, !play.isEmpty {
                HStack(spacing: .appSpace2) {
                    Image(systemName: "text.bubble")
                        .imageScale(.small)
                        .foregroundStyle(Color.appInkFaint)
                    Text(play)
                        .font(.appCallout)
                        .foregroundStyle(Color.appInkSoft)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
        .padding(.appSpace4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle.appShape(.appRadiusLG).fill(Color.appSurface.opacity(0.55)))
        .overlay(RoundedRectangle.appShape(.appRadiusLG).stroke(Color.wcLine, lineWidth: 1))
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .imageScale(.small)
                .foregroundStyle(Color.appInkFaint)
                .padding(.trailing, .appSpace2)
        }
    }

    private func side(code: String, badge: String?, score: Int?, winning: Bool, isHome: Bool) -> some View {
        VStack(alignment: isHome ? .trailing : .leading, spacing: .appSpace2) {
            HStack(spacing: .appSpace3) {
                if isHome, let score {
                    scoreText(score, winning: winning)
                }
                WCBadge(url: badge, size: 44)
                if !isHome, let score {
                    scoreText(score, winning: winning)
                }
            }
            Text(code)
                .font(.appHeadline)
                .foregroundStyle(winning || score == nil ? Color.appInk : Color.appInkSoft)
        }
    }

    private func scoreText(_ value: Int, winning: Bool) -> some View {
        Text("\(value)")
            .font(.appScore)
            .fontWeight(winning ? .heavy : .regular)
            .foregroundStyle(winning ? Color.appInk : Color.appInkSoft)
    }

    @ViewBuilder
    private var center: some View {
        switch state {
        case .live:
            HStack(spacing: 6) {
                WCLiveDot(size: 7)
                Text(game.strProgress ?? "LIVE")
                    .font(.appCaption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.appLive)
            }
        case .final:
            VStack(spacing: 2) {
                Text("FULL TIME")
                    .font(.appFootnote)
                    .tracking(1.2)
                    .foregroundStyle(Color.appInkFaint)
                if let aggregate = game.aggregateScore, !aggregate.isEmpty {
                    Text(aggregate)
                        .font(.appCaption)
                        .foregroundStyle(Color.appInkFaint)
                }
            }
        case .pre:
            VStack(spacing: 2) {
                Text(wcKickoff(game.standardDate))
                    .font(.appCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appInk)
                if let countdown = wcCountdown(to: game.standardDate) {
                    Text(countdown)
                        .font(.appCaption)
                        .foregroundStyle(Color.appInkSoft)
                }
            }
        }
    }
}

// MARK: - Fixture ticker row

/// One tabular line per match — `MEX ⚑ 1–0 ⚑ CZE  63'` — so the matchday reads
/// as the same data system as the group tables below it.
private struct WCFixtureRow: View {
    let gameWithTeams: GameWithTeams
    var showDivider: Bool = true

    private var game: Game { gameWithTeams.game }
    private var state: WCMatchState { wcState(game) }
    private var hasScore: Bool { state != .pre }
    private var awayScore: Int { Int(game.intAwayScore ?? "") ?? 0 }
    private var homeScore: Int { Int(game.intHomeScore ?? "") ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: .appSpace2) {
                HStack(spacing: .appSpace2) {
                    codeText(wcCode(gameWithTeams.awayTeam, fallback: game.strAwayTeam),
                             winning: hasScore && awayScore > homeScore)
                    WCBadge(url: game.strAwayTeamBadge, size: 19)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                centerColumn
                    .frame(width: 64)

                HStack(spacing: .appSpace2) {
                    WCBadge(url: game.strHomeTeamBadge, size: 19)
                    codeText(wcCode(gameWithTeams.homeTeam, fallback: game.strHomeTeam),
                             winning: hasScore && homeScore > awayScore)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                statusColumn
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.vertical, .appSpace3)
            .padding(.horizontal, .appSpace2)
            .contentShape(Rectangle())

            if showDivider {
                Divider().overlay(Color.appDivider)
            }
        }
    }

    private func codeText(_ code: String, winning: Bool) -> some View {
        Text(code)
            .font(.appCaption)
            .fontWeight(winning ? .bold : .medium)
            .foregroundStyle(winning || !hasScore ? Color.appInk : Color.appInkSoft)
    }

    @ViewBuilder
    private var centerColumn: some View {
        if hasScore {
            HStack(spacing: 4) {
                Text("\(awayScore)")
                    .fontWeight(awayScore > homeScore ? .bold : .regular)
                    .foregroundStyle(awayScore > homeScore ? Color.appInk : Color.appInkSoft)
                Text("–").foregroundStyle(Color.appInkFaint)
                Text("\(homeScore)")
                    .fontWeight(homeScore > awayScore ? .bold : .regular)
                    .foregroundStyle(homeScore > awayScore ? Color.appInk : Color.appInkSoft)
            }
            .font(.appCallout)
            .monospacedDigit()
        } else {
            Text(wcKickoff(game.standardDate))
                .font(.appCaption)
                .foregroundStyle(Color.appInkSoft)
        }
    }

    @ViewBuilder
    private var statusColumn: some View {
        switch state {
        case .live:
            HStack(spacing: 4) {
                WCLiveDot(size: 5)
                Text(game.strProgress ?? "LIVE")
                    .font(.appFootnote)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(Color.appLive)
        case .final:
            Text("FT")
                .font(.appFootnote)
                .tracking(1)
                .foregroundStyle(Color.appInkFaint)
        case .pre:
            Text(wcCountdown(to: game.standardDate)?.replacingOccurrences(of: "in ", with: "") ?? "")
                .font(.appFootnote)
                .foregroundStyle(Color.appInkFaint)
                .lineLimit(1)
        }
    }
}

// MARK: - Compact group card

/// One narrow standings card for the horizontal rail: rank · flag · code ·
/// W-L-D · Pts, with qualifying ranks in mint.
private struct WCGroupCard: View {
    let group: Child

    private var entries: [Entry] { group.standings?.entries ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            HStack(alignment: .firstTextBaseline) {
                Text((group.name ?? "Group").uppercased())
                    .font(.appFootnote)
                    .tracking(1.2)
                    .foregroundStyle(Color.appInkFaint)
                Spacer()
                Text("W-L-D · PTS")
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.appInkFaint.opacity(0.7))
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                row(rank: index + 1, entry: entry)
            }
        }
        .padding(.appSpace3)
        .frame(width: 196, alignment: .leading)
        .background(RoundedRectangle.appShape(.appRadiusLG).fill(Color.appSurface))
        .overlay(RoundedRectangle.appShape(.appRadiusLG).stroke(Color.wcLine, lineWidth: 1))
    }

    private func row(rank: Int, entry: Entry) -> some View {
        // Top two qualify for the knockout stage — rank in mint.
        let qualifies = rank <= 2
        return HStack(spacing: 7) {
            Text("\(rank)")
                .font(.appCaption)
                .monospacedDigit()
                .foregroundStyle(qualifies ? Color.wcMint : Color.appInkFaint)
                .frame(width: 12, alignment: .leading)
            WCBadge(url: entry.team?.logos?.first?.href, size: 16)
            Text(teamCode(entry))
                .font(.appCaption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appInk)
            Spacer(minLength: 4)
            Text(record(entry))
                .font(.appCaption)
                .monospacedDigit()
                .foregroundStyle(Color.appInkSoft)
            Text(stat(entry, "points"))
                .font(.appCaption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.appInk)
                .frame(width: 20, alignment: .trailing)
        }
    }

    private func teamCode(_ entry: Entry) -> String {
        if let abbr = entry.team?.abbreviation, !abbr.isEmpty { return abbr.uppercased() }
        let name = entry.team?.shortDisplayName ?? entry.team?.displayName ?? "—"
        return String(name.prefix(3)).uppercased()
    }

    private func record(_ entry: Entry) -> String {
        "\(stat(entry, "wins"))-\(stat(entry, "losses"))-\(stat(entry, "ties"))"
    }

    private func stat(_ entry: Entry, _ name: String) -> String {
        guard let stat = entry.stats?.first(where: { $0.name == name }) else { return "-" }
        return stat.displayValue ?? (stat.value.map { "\(Int($0))" } ?? "-")
    }
}

// MARK: - Previews

#if DEBUG

/// Mock matchday builder shared by the hero previews. `Game.id` falls back to
/// a fresh UUID when `idEvent` is nil, so every mock needs a stable event ID.
private enum WCHeroMock {
    static let wcID = String(Leagues.FIFA_World_Cup.rawValue)

    static func match(_ away: String, _ home: String, awayScore: String? = nil, homeScore: String? = nil,
                      status: String, progress: String? = nil, lastPlay: String? = nil,
                      offsetMinutes: Int) -> Game {
        Game(
            idEvent: "\(away)-\(home)-\(offsetMinutes)",
            idLeague: wcID,
            strHomeTeam: home,
            strAwayTeam: away,
            intHomeScore: homeScore,
            intAwayScore: awayScore,
            strStatus: status,
            strProgress: progress,
            lastPlay: lastPlay,
            isoDate: Date().addingTimeInterval(TimeInterval(offsetMinutes * 60))
        )
    }

    // Group standings after matchday 2 — mirrors the design prototype's data.
    static func standings() -> [Child] {
        func stat(_ name: String, _ value: Int) -> Stat {
            Stat(name: name, displayName: nil, shortDisplayName: nil, description: nil,
                 abbreviation: nil, type: nil, value: Double(value), displayValue: "\(value)",
                 id: nil, summary: nil)
        }
        func entry(_ abbr: String, _ name: String, w: Int, l: Int, d: Int, pts: Int) -> Entry {
            let team = ESPNTeam(id: abbr, uid: nil, slug: nil, abbreviation: abbr,
                                displayName: name, shortDisplayName: name, name: name, nickname: nil,
                                location: nil, color: nil, alternateColor: nil,
                                isActive: true, isAllStar: false, logos: nil, links: nil)
            return Entry(team: team, note: nil,
                         stats: [stat("wins", w), stat("losses", l), stat("ties", d), stat("points", pts)])
        }
        func group(_ name: String, _ entries: [Entry]) -> Child {
            Child(uid: nil, id: name, name: "Group \(name)", abbreviation: name,
                  standings: Standings(id: nil, name: nil, displayName: nil, links: nil,
                                       season: nil, seasonType: nil, entries: entries))
        }
        return [
            group("A", [entry("MEX", "Mexico", w: 2, l: 0, d: 0, pts: 6),
                        entry("CZE", "Czechia", w: 1, l: 1, d: 0, pts: 3),
                        entry("KOR", "South Korea", w: 0, l: 1, d: 1, pts: 1),
                        entry("RSA", "South Africa", w: 0, l: 1, d: 1, pts: 1)]),
            group("B", [entry("SUI", "Switzerland", w: 1, l: 0, d: 1, pts: 4),
                        entry("CAN", "Canada", w: 1, l: 0, d: 1, pts: 4),
                        entry("BIH", "Bosnia", w: 0, l: 1, d: 1, pts: 1),
                        entry("QAT", "Qatar", w: 0, l: 1, d: 1, pts: 1)]),
            group("C", [entry("BRA", "Brazil", w: 2, l: 0, d: 0, pts: 6),
                        entry("MAR", "Morocco", w: 1, l: 1, d: 0, pts: 3),
                        entry("SCO", "Scotland", w: 0, l: 1, d: 1, pts: 1),
                        entry("HAI", "Haiti", w: 0, l: 1, d: 1, pts: 1)]),
        ]
    }

    @MainActor
    static func harness(games: [Game]) -> some View {
        GameViewModel.isSnapshotTesting = true
        WorldCupHeroStandings.seedForPreviews(groups: standings())
        let storage = UserDefaultStorage()
        let favorites = Favorites()
        return NavigationStack {
            ScrollView {
                WorldCupHeroCard()
                    .padding(.appSpace4)
            }
            .background(Color.appBackground)
        }
        .environment(GameViewModel(appStorage: storage, favorites: favorites, totalGames: games))
        .environment(storage)
        .environment(favorites)
        .preferredColorScheme(.dark)
    }
}

#Preview("Multi-live · switch") {
    WCHeroMock.harness(games: [
        WCHeroMock.match("Mexico", "Czechia", awayScore: "1", homeScore: "0", status: "in", progress: "63'",
                         lastPlay: "Raúl Jiménez Goal (1) — assisted by H. Lozano", offsetMinutes: -63),
        WCHeroMock.match("South Korea", "South Africa", awayScore: "1", homeScore: "1", status: "in", progress: "38'", offsetMinutes: -38),
        WCHeroMock.match("Switzerland", "Canada", awayScore: "2", homeScore: "1", status: "in", progress: "71'", offsetMinutes: -71),
        WCHeroMock.match("Canada", "Switzerland", status: "pre", offsetMinutes: 130),
        WCHeroMock.match("Brazil", "Scotland", awayScore: "3", homeScore: "1", status: "post", progress: "FT", offsetMinutes: -240),
    ])
}

#Preview("One live") {
    WCHeroMock.harness(games: [
        WCHeroMock.match("Mexico", "Czechia", awayScore: "1", homeScore: "0", status: "in", progress: "63'",
                         lastPlay: "Raúl Jiménez Goal (1) — assisted by H. Lozano", offsetMinutes: -63),
        WCHeroMock.match("Canada", "Switzerland", status: "pre", offsetMinutes: 130),
        WCHeroMock.match("South Korea", "South Africa", status: "pre", offsetMinutes: 280),
        WCHeroMock.match("Brazil", "Scotland", awayScore: "3", homeScore: "1", status: "post", progress: "FT", offsetMinutes: -240),
    ])
}

#Preview("No live · next kickoff") {
    WCHeroMock.harness(games: [
        WCHeroMock.match("Brazil", "Morocco", status: "pre", offsetMinutes: 45),
        WCHeroMock.match("Canada", "Switzerland", status: "pre", offsetMinutes: 130),
        WCHeroMock.match("South Korea", "South Africa", status: "pre", offsetMinutes: 280),
    ])
}

#Preview("Matchday complete") {
    WCHeroMock.harness(games: [
        WCHeroMock.match("Mexico", "Czechia", awayScore: "1", homeScore: "0", status: "post", progress: "FT", offsetMinutes: -300),
        WCHeroMock.match("Switzerland", "Canada", awayScore: "0", homeScore: "1", status: "post", progress: "FT", offsetMinutes: -240),
        WCHeroMock.match("Brazil", "Scotland", awayScore: "3", homeScore: "1", status: "post", progress: "FT", offsetMinutes: -180),
        WCHeroMock.match("Haiti", "Morocco", status: "pre", offsetMinutes: 1100),
    ])
}

#endif
