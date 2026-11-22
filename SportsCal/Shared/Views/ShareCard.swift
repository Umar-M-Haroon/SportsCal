//
//  ShareCard.swift
//  SportsCal
//
//  Share cards: a rendered 1080×1350 (4:5) image of a game, shared with a
//  one-line summary and the game's universal link (sportscal.app/g/<idEvent>),
//  whose web page carries the Smart App Banner for recipients without the app.
//
//  `ShareCardModel` resolves what the card says from a `Game` (pure, so the
//  previews and the share text read the same values). `ShareCardView` draws it on
//  a fixed dark card. `ShareCardButton` is the toolbar entry point: it pre-fetches
//  the team logos (ImageRenderer won't wait for async images), renders the card,
//  and hands a PNG `Transferable` to `ShareLink`, with the summary and link as the
//  message. Until the image is ready it shares the plain link.
//

import SwiftUI
import SportsCalModel
import NukeUI
import Nuke
import ImageIO
import UniformTypeIdentifiers

// MARK: - Model

struct ShareCardModel {
    enum Phase: String { case upcoming, live, final }

    struct Side {
        var name: String
        var code: String
        var color: Color
        var score: String?
        var isWinner: Bool
        var badgeURL: URL?
        var detail: String?
    }

    struct Row {
        var position: String
        var name: String
        var value: String?
        var valueColor: Color?
        var marker: Color?
    }

    struct TennisSide {
        var name: String
        var seed: Int?
        var sets: [String]
        var isWinner: Bool
        var isServing: Bool
    }

    enum Content {
        case matchup(first: Side, second: Side)
        case leaderboard(title: String, subtitle: String?, leaderLabel: String?, rows: [Row])
        case tennis(first: TennisSide, second: TennisSide, title: String?)
    }

    var sport: SportType?
    var leagueName: String
    var phase: Phase
    /// "Final", "6:30 - 2nd", "Sun, Nov 23 · 4:25 PM".
    var statusText: String
    var content: Content
    var url: URL?
    /// "Chiefs 27–20 Bills · Final" — the share sheet's subject and message lead.
    var summary: String

    /// The share message: the summary, then the link.
    var message: String {
        [summary, url?.absoluteString].compactMap { $0 }.joined(separator: "\n")
    }

    /// Short display host + path for the card footer ("sportscal.app/g/123").
    var footerLink: String {
        guard let url else { return DeepLink.host }
        return (url.host ?? DeepLink.host) + url.path
    }

    var badgeURLs: [URL] {
        guard case .matchup(let first, let second) = content else { return [] }
        return [first.badgeURL, second.badgeURL].compactMap { $0 }
    }

    /// Stable telemetry value for the sport ("basketball", "racing", …).
    var sportKey: String { sport?.rawValue ?? "unknown" }

    init(sport: SportType?, leagueName: String, phase: Phase, statusText: String,
         content: Content, url: URL?, summary: String) {
        self.sport = sport
        self.leagueName = leagueName
        self.phase = phase
        self.statusText = statusText
        self.content = content
        self.url = url
        self.summary = summary
    }

    init(game: Game, homeTeam: Team? = nil, awayTeam: Team? = nil,
         f1Standings: F1Standings? = nil, now: Date = Date()) {
        let league = game.idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:))
        let sport = league.map(SportType.init(league:))
        let leagueName = league?.leagueName ?? game.strLeague ?? ""
        let url = game.idEvent.flatMap { DeepLink.url(for: .game(idEvent: $0)) }
        let phase = Self.phase(for: game)

        let content: Content
        let statusText: String
        let summary: String

        if game.isRace {
            (content, statusText, summary) = Self.race(game, phase: phase, standings: f1Standings, now: now)
        } else if game.isTennisMatch {
            (content, statusText, summary) = Self.tennis(game, phase: phase, now: now)
        } else if game.isIndividualSport {
            (content, statusText, summary) = Self.tournament(game, phase: phase, now: now)
        } else {
            (content, statusText, summary) = Self.matchup(game, home: homeTeam, away: awayTeam, sport: sport,
                                                           phase: phase, now: now)
        }
        self.init(sport: sport, leagueName: leagueName, phase: phase, statusText: statusText,
                  content: content, url: url, summary: summary)
    }

    // MARK: Phase and dates

    private static func phase(for game: Game) -> Phase {
        if game.isRace {
            switch game.raceWeekendStatus {
            case .live: return .live
            case .finished: return .final
            case .upcoming: return .upcoming
            case .none: break
            }
        }
        switch game.scheduleState() {
        case .upcoming: return .upcoming
        case .live: return .live
        case .final: return .final
        }
    }

    /// Card date line: "Sun, Nov 23 · 4:25 PM" in the user's locale.
    static func cardDate(_ date: Date, timeTBD: Bool) -> String {
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let time = timeTBD ? "Time TBD" : date.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(time)"
    }

    /// Share text date: "Sun 4:25 PM" within the week, else "Sun, Nov 30, 4:25 PM".
    static func shortDate(_ date: Date, timeTBD: Bool, now: Date) -> String {
        let withinWeek = date.timeIntervalSince(now) < 6 * 24 * 3600 && date > now.addingTimeInterval(-12 * 3600)
        if timeTBD {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return withinWeek
            ? date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    /// A team color legible on the dark card (near-black navies lift toward white).
    private static func cardColor(_ hex: String?, fallback: Color) -> Color {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let base = Color(hex: hex) ?? fallback
        // Stricter than the app-wide `legible`: the card is always near-black, and
        // navies just above its 6% cut (Chelsea, Yankees) were unreadable.
        let resolved = base.resolve(in: environment)
        let luminance = 0.2126 * Double(resolved.linearRed)
            + 0.7152 * Double(resolved.linearGreen)
            + 0.0722 * Double(resolved.linearBlue)
        return luminance < 0.12 ? base.mix(with: .white, by: 0.5) : base
    }

    // MARK: Team sports

    private static func matchup(_ game: Game, home: Team?, away: Team?, sport: SportType?, phase: Phase,
                                now: Date) -> (Content, String, String) {
        let winner = phase == .final ? game.winningSide : nil
        let showScores = phase != .upcoming
            && Int(game.intHomeScore ?? "") != nil && Int(game.intAwayScore ?? "") != nil

        func side(_ which: GameSituation.Side) -> Side {
            let isHome = which == .home
            let team = isHome ? home : away
            let name = team?.strTeam ?? (isHome ? game.strHomeTeam : game.strAwayTeam)
            let abbreviation = isHome ? game.homeAbbreviation : game.awayAbbreviation
            let code = abbreviation ?? team?.strTeamShort ?? String(name.prefix(3)).uppercased()
            let badge = team?.strTeamBadge ?? (isHome ? game.strHomeTeamBadge : game.strAwayTeamBadge)
            let record = isHome ? game.homeRecord : game.awayRecord
            return Side(
                name: name,
                code: code,
                color: cardColor(isHome ? game.homeTeamColor : game.awayTeamColor,
                                 fallback: isHome ? .blue : .red),
                score: showScores ? (isHome ? game.intHomeScore : game.intAwayScore) : nil,
                isWinner: winner == which,
                badgeURL: badge.flatMap(badgeURL),
                detail: phase == .upcoming ? record : nil
            )
        }

        let sides = game.displayedSides
        let first = side(sides.first)
        let second = side(sides.second)

        let statusText: String
        let summary: String
        switch phase {
        case .upcoming:
            if let date = game.standardDate {
                statusText = cardDate(date, timeTBD: game.isTimeTBD)
                summary = "\(game.matchupTitle) · \(shortDate(date, timeTBD: game.isTimeTBD, now: now))"
            } else {
                statusText = game.displayStatus ?? "Upcoming"
                summary = game.matchupTitle
            }
        case .live, .final:
            statusText = game.displayStatus ?? (phase == .live ? "Live" : "Final")
            if let a = first.score, let b = second.score {
                summary = "\(first.name) \(a)–\(b) \(second.name) · \(statusText)"
            } else {
                summary = "\(game.matchupTitle) · \(statusText)"
            }
        }
        return (.matchup(first: first, second: second), statusText, summary)
    }

    /// TheSportsDB badges come in several sizes; `/medium` (500px) covers the
    /// 104pt slot at 3× without pulling the full-size original.
    private static func badgeURL(_ string: String) -> URL? {
        URL(string: string.contains("thesportsdb.com") ? string + "/medium" : string)
    }

    // MARK: Tennis

    private static func tennis(_ game: Game, phase: Phase, now: Date) -> (Content, String, String) {
        let sets = game.tennisSets
        let winner = phase == .final ? game.tennisMatchWinner : nil
        let server = game.tennisServer

        func side(_ which: GameSituation.Side) -> TennisSide {
            TennisSide(
                name: which == .home ? game.strHomeTeam : game.strAwayTeam,
                seed: which == .home ? game.tennisHomeSeed : game.tennisAwaySeed,
                sets: phase == .upcoming ? [] : sets.map { $0.text(for: which) },
                isWinner: winner == which,
                isServing: server == which
            )
        }
        let sides = game.displayedSides
        let first = side(sides.first)
        let second = side(sides.second)
        let tournament = game.tournamentName ?? game.strLeague
        let title = [tournament, game.round].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")

        let statusText: String
        var parts: [String]
        switch phase {
        case .upcoming:
            let date = game.standardDate
            statusText = date.map { cardDate($0, timeTBD: game.isTimeTBD) } ?? "Upcoming"
            parts = ["\(first.name) vs \(second.name)"]
            if let date { parts.append(shortDate(date, timeTBD: game.isTimeTBD, now: now)) }
        case .live:
            statusText = game.tennisStoppageText ?? "Live"
            parts = ["\(first.name) vs \(second.name)", setLine(sets, first: sides.first), statusText]
        case .final:
            statusText = [game.displayStatus ?? "Final", game.tennisResultMarker].compactMap { $0 }
                .joined(separator: " · ")
            if let winner {
                let loser: GameSituation.Side = winner == .home ? .away : .home
                let winnerName = winner == .home ? game.strHomeTeam : game.strAwayTeam
                let loserName = loser == .home ? game.strHomeTeam : game.strAwayTeam
                parts = ["\(winnerName) def. \(loserName) \(setLine(sets, first: winner))"
                    + (game.tennisResultMarker.map { " \($0)" } ?? "")]
            } else {
                parts = ["\(first.name) vs \(second.name)", setLine(sets, first: sides.first), statusText]
            }
        }
        if let tournament, !tournament.isEmpty { parts.append(tournament) }
        let summary = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        return (.tennis(first: first, second: second, title: title.isEmpty ? nil : title), statusText, summary)
    }

    /// "6-4 3-6 7-6", from `first`'s side.
    private static func setLine(_ sets: [TennisSet], first: GameSituation.Side) -> String {
        let second: GameSituation.Side = first == .home ? .away : .home
        return sets.map { "\($0.text(for: first))-\($0.text(for: second))" }.joined(separator: " ")
    }

    // MARK: Golf / tennis tournaments

    private static func tournament(_ game: Game, phase: Phase, now: Date) -> (Content, String, String) {
        let title = game.tournamentName ?? game.strHomeTeam
        let board = game.resolvedLeaderboard
        let positions = board.golfPositionLabelsByName()
        var rows = board.prefix(5).map { entry in
            Row(position: positions[entry.name] ?? "\(entry.position)", name: entry.name, value: entry.score,
                valueColor: GolfScoreStyle.color(toPar: entry.score), marker: nil)
        }
        if rows.isEmpty, phase != .upcoming, !game.strAwayTeam.isEmpty, game.strAwayTeam != "TBD" {
            rows = [Row(position: "1", name: game.strAwayTeam, value: game.intAwayScore, valueColor: nil, marker: nil)]
        }
        let leaderLabel = phase == .final ? "Winner" : (phase == .live ? "Leader" : nil)

        let statusText: String
        var parts = [title]
        switch phase {
        case .upcoming:
            let date = game.standardDate
            statusText = date.map { cardDate($0, timeTBD: false) } ?? "Upcoming"
            if let date { parts.append(shortDate(date, timeTBD: false, now: now)) }
        case .live, .final:
            statusText = game.displayStatus ?? (phase == .live ? "Live" : "Final")
            parts.append(statusText)
            if let leader = rows.first, let leaderLabel {
                parts.append("\(leaderLabel): \(leader.name)" + (leader.value.map { " \($0)" } ?? ""))
            }
        }
        let content = Content.leaderboard(title: title, subtitle: game.venueName, leaderLabel: leaderLabel,
                                          rows: phase == .upcoming ? [] : rows)
        return (content, statusText, parts.joined(separator: " · "))
    }

    // MARK: Races

    private static func race(_ game: Game, phase: Phase, standings: F1Standings?,
                             now: Date) -> (Content, String, String) {
        let title = game.strHomeTeam
        let source = game.featuredSession.flatMap { $0.leaderboard.isEmpty ? nil : $0 }
        let entries: [LeaderboardEntry] = source.map {
            Array($0.leaderboard.filter { $0.position > 0 }.sorted { $0.position < $1.position }.prefix(3))
        } ?? Array(game.resolvedLeaderboard.prefix(3))
        let leaderLabel = source?.leaderTitle ?? (phase == .final ? "Winner" : "Leader")
        let rows: [Row] = entries.enumerated().map { index, entry in
            let marker: Color? = {
                if let manufacturer = entry.stockCar?.manufacturer,
                   let hex = NASCARVocabulary.manufacturerColorHex(manufacturer) {
                    return Color(hex: hex)
                }
                return entry.constructor.map { F1GapRibbonView.colorForConstructorName($0, standings: standings) }
            }()
            return Row(position: "\(entry.position)", name: entry.name,
                       value: index == 0 ? leaderLabel : (entry.gap ?? entry.score),
                       valueColor: nil, marker: marker)
        }
        let subtitle: String? = game.circuitInfo.map { "\($0.circuitName) · \($0.locality), \($0.country)" }
            ?? game.venueName

        let statusText: String
        var parts = [title]
        switch game.raceWeekendStatus {
        case .upcoming(let label, let date) where phase == .upcoming:
            statusText = "\(label) · \(cardDate(date, timeTBD: false))"
            parts.append("\(label) \(shortDate(date, timeTBD: false, now: now))")
        case .live(let name):
            if let state = game.liveSessionEntry?.raceState, state.lap > 0 {
                statusText = "\(name) · \(state.totalLaps > 0 ? state.lapLabel : "Lap \(state.lap)")"
            } else {
                statusText = "\(name) · Live"
            }
            parts.append(statusText)
        default:
            switch phase {
            case .upcoming:
                let date = game.standardDate
                statusText = date.map { cardDate($0, timeTBD: false) } ?? "Upcoming"
                if let date { parts.append(shortDate(date, timeTBD: false, now: now)) }
            case .live:
                statusText = game.strProgress ?? game.displayStatus ?? "Live"
                parts.append(statusText)
            case .final:
                statusText = "Final"
                parts.append(statusText)
            }
        }
        if phase != .upcoming, let leader = rows.first {
            parts.append("\(leaderLabel): \(leader.name)")
        }
        let content = Content.leaderboard(title: title, subtitle: subtitle, leaderLabel: nil,
                                          rows: phase == .upcoming ? [] : rows)
        return (content, statusText, parts.joined(separator: " · "))
    }
}

// MARK: - Card view

/// The card, drawn at 360×450pt and rendered at 3× (1080×1350px). A fixed dark
/// card, so it reads the same wherever it's posted.
struct ShareCardView: View {
    static let size = CGSize(width: 360, height: 450)
    static let renderScale: CGFloat = 3

    let model: ShareCardModel
    /// Pre-fetched team logos by URL; a missing one falls back to a monogram.
    var logos: [URL: Image] = [:]
    var accent: Color = .accentColor

    private let background = Color(red: 0.055, green: 0.063, blue: 0.086)
    private let ink = Color.white
    private let inkSoft = Color.white.opacity(0.62)
    private let inkFaint = Color.white.opacity(0.38)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 18)
            Spacer(minLength: 0)
            switch model.content {
            case .matchup(let first, let second):
                matchup(first, second)
            case .leaderboard(let title, let subtitle, let leaderLabel, let rows):
                leaderboard(title: title, subtitle: subtitle, leaderLabel: leaderLabel, rows: rows)
            case .tennis(let first, let second, let title):
                tennis(first, second, title: title)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            ZStack {
                background
                RadialGradient(colors: [glowColor.opacity(0.32), .clear], center: .top,
                               startRadius: 0, endRadius: 320)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var glowColor: Color {
        if case .matchup(let first, _) = model.content, model.phase == .final {
            return first.isWinner ? first.color : (model.sport?.color ?? accent)
        }
        return model.sport?.color ?? accent
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if let sport = model.sport {
                Image(systemName: sport.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(sport.color)
            }
            Text(model.leagueName.uppercased())
                .font(.system(size: 13, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(inkSoft)
                .lineLimit(1)
            Spacer(minLength: 8)
            phasePill
        }
    }

    @ViewBuilder
    private var phasePill: some View {
        switch model.phase {
        case .live:
            HStack(spacing: 5) {
                Circle().fill(.white).frame(width: 6, height: 6)
                Text("LIVE")
            }
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.red, in: Capsule())
        case .final:
            Text("FINAL")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.14), in: Capsule())
        case .upcoming:
            Text("UPCOMING")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(accent.opacity(0.18), in: Capsule())
        }
    }

    // MARK: Matchup

    private func matchup(_ first: ShareCardModel.Side, _ second: ShareCardModel.Side) -> some View {
        VStack(spacing: 22) {
            HStack(alignment: .top, spacing: 0) {
                teamColumn(first, dimmed: model.phase == .final && second.isWinner)
                    .frame(maxWidth: .infinity)
                teamColumn(second, dimmed: model.phase == .final && first.isWinner)
                    .frame(maxWidth: .infinity)
            }
            centerBlock(first, second)
            HStack(spacing: 3) {
                Capsule().fill(first.color)
                Capsule().fill(second.color)
            }
            .frame(height: 4)
            .padding(.horizontal, 30)
        }
    }

    private func teamColumn(_ side: ShareCardModel.Side, dimmed: Bool) -> some View {
        VStack(spacing: 10) {
            logo(side)
                .frame(width: 104, height: 104)
            Text(side.code)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(side.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(side.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(inkSoft)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(height: 34, alignment: .top)
            if let detail = side.detail {
                Text(detail)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(inkFaint)
            }
        }
        .padding(.horizontal, 6)
        .opacity(dimmed ? 0.55 : 1)
    }

    @ViewBuilder
    private func logo(_ side: ShareCardModel.Side) -> some View {
        if let url = side.badgeURL, let image = logos[url] {
            image
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        } else {
            ZStack {
                // No logo: a team-colour monogram. Not the code — it's printed
                // right below, and "BOS" over "BOS" read as a glitch.
                Circle().fill(side.color.opacity(0.22))
                Circle().strokeBorder(side.color.opacity(0.7), lineWidth: 2)
                Text(String(side.name.prefix(1)))
                    .font(.system(size: 46, weight: .black))
                    .foregroundStyle(side.color)
            }
        }
    }

    @ViewBuilder
    private func centerBlock(_ first: ShareCardModel.Side, _ second: ShareCardModel.Side) -> some View {
        if let a = first.score, let b = second.score {
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    scoreText(a, emphasized: model.phase != .final || first.isWinner)
                    Text("–")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(inkFaint)
                    scoreText(b, emphasized: model.phase != .final || second.isWinner)
                }
                Text(model.statusText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.phase == .live ? Color.red : inkSoft)
                    .lineLimit(1)
            }
        } else {
            VStack(spacing: 6) {
                Text(model.statusText)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func scoreText(_ score: String, emphasized: Bool) -> some View {
        Text(score)
            .font(.system(size: 64, weight: emphasized ? .black : .medium).monospacedDigit())
            .foregroundStyle(emphasized ? ink : inkFaint)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    // MARK: Leaderboard (golf, races, tennis tournaments)

    private func leaderboard(title: String, subtitle: String?, leaderLabel: String?,
                             rows: [ShareCardModel.Row]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(model.statusText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.phase == .live ? Color.red : (model.phase == .upcoming ? accent : inkSoft))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        leaderboardRow(row, isLeader: index == 0, leaderLabel: leaderLabel)
                        if index < rows.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func leaderboardRow(_ row: ShareCardModel.Row, isLeader: Bool, leaderLabel: String?) -> some View {
        HStack(spacing: 10) {
            Text(row.position)
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(isLeader ? accent : inkFaint)
                .frame(width: 30, alignment: .leading)
            if let marker = row.marker {
                RoundedRectangle(cornerRadius: 1.5).fill(marker).frame(width: 3, height: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.system(size: isLeader ? 18 : 16, weight: isLeader ? .bold : .medium))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // Without this the value column took width first and each
                    // row's name shrank by a different amount.
                    .layoutPriority(1)
                if isLeader, let leaderLabel {
                    Text(leaderLabel.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(inkFaint)
                }
            }
            Spacer(minLength: 8)
            if let value = row.value {
                Text(value)
                    .font(.system(size: 15, weight: isLeader ? .bold : .semibold).monospacedDigit())
                    .foregroundStyle(row.valueColor ?? (isLeader ? ink : inkSoft))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.vertical, isLeader ? 13 : 10)
    }

    // MARK: Tennis match

    private func tennis(_ first: ShareCardModel.TennisSide, _ second: ShareCardModel.TennisSide,
                        title: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                if let title {
                    Text(title)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                Text(model.statusText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.phase == .live ? Color.red : (model.phase == .upcoming ? accent : inkSoft))
                    .lineLimit(1)
            }
            VStack(spacing: 0) {
                tennisRow(first, dimmed: model.phase == .final && second.isWinner)
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                tennisRow(second, dimmed: model.phase == .final && first.isWinner)
            }
            .padding(.horizontal, 14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func tennisRow(_ side: ShareCardModel.TennisSide, dimmed: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(side.name)
                        .font(.system(size: 19, weight: side.isWinner ? .heavy : .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if side.isWinner {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    if side.isServing {
                        Circle().fill(Color.yellow).frame(width: 7, height: 7)
                    }
                }
                if let seed = side.seed {
                    Text("Seed \(seed)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(inkFaint)
                }
            }
            Spacer(minLength: 8)
            ForEach(Array(side.sets.enumerated()), id: \.offset) { _, set in
                Text(set)
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(ink)
                    .frame(minWidth: 26)
            }
        }
        .padding(.vertical, 14)
        .opacity(dimmed ? 0.55 : 1)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(accent)
                .frame(width: 14, height: 14)
                .overlay {
                    Image(systemName: "calendar")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
            Text("Scoreline")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ink.opacity(0.85))
            Spacer(minLength: 8)
            Text(model.footerLink)
                .font(.system(size: 12, weight: .medium).monospaced())
                .foregroundStyle(inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.top, 18)
    }
}

// MARK: - Rendering

enum ShareCardRenderer {
    /// Loads the card's logos through Nuke's pipeline (usually a memory/disk cache hit
    /// since the detail screen already showed them). A slow or failed logo is skipped
    /// and the card draws a monogram instead.
    static func loadLogos(for urls: [URL]) async -> [URL: Image] {
        await withTaskGroup(of: (URL, Image?).self) { group in
            for url in urls {
                group.addTask {
                    guard let image = try? await ImagePipeline.shared.image(for: url) else { return (url, nil) }
                    #if canImport(UIKit)
                    return (url, Image(uiImage: image))
                    #else
                    return (url, Image(nsImage: image))
                    #endif
                }
            }
            var result: [URL: Image] = [:]
            for await (url, image) in group {
                if let image { result[url] = image }
            }
            return result
        }
    }

    /// Renders the card to a 1080×1350 PNG plus a preview image.
    @MainActor
    static func render(_ model: ShareCardModel, logos: [URL: Image], accent: Color) -> (png: Data, preview: Image)? {
        let renderer = ImageRenderer(content: ShareCardView(model: model, logos: logos, accent: accent))
        renderer.scale = ShareCardView.renderScale
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage, let png = pngData(cgImage) else { return nil }
        return (png, Image(decorative: cgImage, scale: ShareCardView.renderScale))
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// The rendered card as a share item. Records `share_card_shared` the first time a
/// share target actually pulls the image (ShareLink offers no completion callback).
nonisolated struct ShareCardImage: Transferable, Sendable {
    let png: Data
    let fileName: String
    let sport: String
    let phase: String
    let once = ShareOnceFlag()

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            if card.once.claim() {
                let fields = ["sport": card.sport, "state": card.phase]
                await MainActor.run {
                    MonetizationTelemetry.record(MonetizationTelemetry.Event.shareCardShared, fields)
                }
            }
            return card.png
        }
        .suggestedFileName { $0.fileName }
    }
}

/// A thread-safe one-shot latch.
nonisolated final class ShareOnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !fired else { return false }
        fired = true
        return true
    }
}

// MARK: - Toolbar entry point

/// The detail toolbar's share button: the rendered card plus the summary and link,
/// or just the link while the card renders (or if it can't).
struct ShareCardButton: View {
    let game: Game
    var homeTeam: Team?
    var awayTeam: Team?

    @Environment(GameViewModel.self) private var viewModel
    @State private var card: ShareCardImage?
    @State private var preview: Image?
    @State private var logos: [URL: Image] = [:]

    private var model: ShareCardModel {
        ShareCardModel(game: game, homeTeam: homeTeam, awayTeam: awayTeam, f1Standings: viewModel.f1Standings)
    }

    /// Re-render when anything the card shows changes (live score, clock, leaderboard).
    private var renderKey: String {
        [game.idEvent, game.intHomeScore, game.intAwayScore, game.strStatus, game.strProgress,
         game.lastPlay, game.resolvedLeaderboard.prefix(5).map { "\($0.name)\($0.score)" }.joined(),
         homeTeam?.strTeamBadge, awayTeam?.strTeamBadge]
            .map { $0 ?? "" }.joined(separator: "|")
    }

    var body: some View {
        let model = model
        Group {
            if let card, let preview {
                ShareLink(
                    item: card,
                    subject: Text(model.summary),
                    message: Text(model.message),
                    preview: SharePreview(model.summary, image: preview)
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            } else if let url = model.url {
                ShareLink(item: url, subject: Text(model.summary), message: Text(model.summary)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .accessibilityLabel("Share")
        .task(id: renderKey) {
            let missing = model.badgeURLs.filter { logos[$0] == nil }
            if !missing.isEmpty {
                logos.merge(await ShareCardRenderer.loadLogos(for: missing)) { $1 }
            }
            guard !Task.isCancelled,
                  let rendered = ShareCardRenderer.render(model, logos: logos, accent: .appAccent) else { return }
            card = ShareCardImage(png: rendered.png,
                                  fileName: "Scoreline-\(game.idEvent ?? "game").png",
                                  sport: model.sportKey, phase: model.phase.rawValue)
            preview = rendered.preview
        }
    }
}

// MARK: - Previews

private enum ShareCardPreviewData {
    static let now = Date()

    static func team(_ name: String, _ code: String) -> Team {
        Team(strTeam: name, strTeamShort: code)
    }

    static var upcoming: ShareCardModel {
        let game = Game(idEvent: "2001", idLeague: "\(Leagues.nfl.rawValue)",
                        strHomeTeam: "Buffalo Bills", strAwayTeam: "Kansas City Chiefs",
                        strStatus: "NS", isoDate: now.addingTimeInterval(2 * 24 * 3600),
                        homeTeamColor: "00338D", awayTeamColor: "E31837",
                        homeRecord: "9-2", awayRecord: "10-1")
        return ShareCardModel(game: game, homeTeam: team("Buffalo Bills", "BUF"),
                              awayTeam: team("Kansas City Chiefs", "KC"))
    }

    static var live: ShareCardModel {
        let game = Game(idEvent: "2002", idLeague: "\(Leagues.nba.rawValue)",
                        strHomeTeam: "Los Angeles Lakers", strAwayTeam: "Boston Celtics",
                        intHomeScore: "88", intAwayScore: "91", strStatus: "in", strProgress: "4:12 - 4th",
                        isoDate: now, homeTeamColor: "552583", awayTeamColor: "007A33")
        return ShareCardModel(game: game, homeTeam: team("Los Angeles Lakers", "LAL"),
                              awayTeam: team("Boston Celtics", "BOS"))
    }

    static var final: ShareCardModel {
        let game = Game(idEvent: "2003", idLeague: "\(Leagues.English_Premier_League.rawValue)",
                        strHomeTeam: "Arsenal", strAwayTeam: "Chelsea",
                        intHomeScore: "2", intAwayScore: "1", strStatus: "post", strProgress: "FT",
                        isCompleted: true, isoDate: now.addingTimeInterval(-3 * 3600),
                        homeTeamColor: "EF0107", awayTeamColor: "034694")
        return ShareCardModel(game: game, homeTeam: team("Arsenal", "ARS"), awayTeam: team("Chelsea", "CHE"))
    }

    static var golf: ShareCardModel {
        ShareCardModel(game: DebugGameFactory.createFakeLiveTournament(sport: .golf, isMajor: true))
    }

    static var race: ShareCardModel {
        ShareCardModel(game: DebugGameFactory.createFakeLiveRace())
    }

    static var tennis: ShareCardModel {
        let game = Game(idEvent: "2004", idLeague: "\(Leagues.atp.rawValue)", idHomeTeam: "1", idAwayTeam: "2",
                        strHomeTeam: "Carlos Alcaraz", strAwayTeam: "Jannik Sinner",
                        intHomeScore: "2", intAwayScore: "1", strStatus: "post", strProgress: "Final",
                        homeLinescores: [6, 3, 7], awayLinescores: [4, 6, 5], isCompleted: true,
                        isoDate: now.addingTimeInterval(-3600), tournamentName: "US Open", round: "Final")
        return ShareCardModel(game: game)
    }
}

#Preview("Upcoming") { ShareCardView(model: ShareCardPreviewData.upcoming) }
#Preview("Live") { ShareCardView(model: ShareCardPreviewData.live) }
#Preview("Final") { ShareCardView(model: ShareCardPreviewData.final) }
#Preview("Golf") { ShareCardView(model: ShareCardPreviewData.golf) }
#Preview("F1") { ShareCardView(model: ShareCardPreviewData.race) }
#Preview("Tennis") { ShareCardView(model: ShareCardPreviewData.tennis) }
