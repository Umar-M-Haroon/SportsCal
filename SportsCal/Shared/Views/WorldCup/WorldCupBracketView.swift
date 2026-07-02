//
//  WorldCupBracketView.swift
//  SportsCal
//
//  Knockout bracket visualization. One column per round (Round of 32 → Final at the
//  2026 tournament) with connector lines that make matches visibly feed forward into
//  the next round. Round structure comes from the server (derived from ESPN), never
//  hardcoded, so the 48-team format renders correctly.
//
//  Each cell carries per-match detail: kickoff date/time, a LIVE pill while in
//  progress, full-time / aggregate state when decided, venue, and scores. Undecided
//  slots show ESPN's placeholder ("Winner Group A"); once a group's standings are
//  final we *project* the qualifying nation into the slot (rendered italic, since it
//  is not yet the official fixture) so the path out of the group stage is legible the
//  moment the group wraps — before ESPN schedules the knockout fixture.
//

import SwiftUI
import SportsCalModel

struct WorldCupBracketView: View {
    let bracket: WorldCupBracket
    /// Group standings (ESPN `children`) used to project qualifiers into TBD slots.
    var groups: [Child] = []

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites

    private var accent: Color { .app(.soccer) }

    // Layout. The bracket lays out as a deterministic tree: round `r` (0-based) packs
    // its cells into slots of height `totalHeight / count`, so each later round's cell
    // sits centered between the two feeder cells of the previous round and the
    // connector elbows line up analytically — no GeometryReader needed.
    private let cardWidth: CGFloat = 196
    private let unitSlot: CGFloat = 132      // height of one Round-of-32 slot (vertical gap between games)
    private let connectorWidth: CGFloat = 52 // horizontal gap between rounds
    private let headerHeight: CGFloat = 30
    private let headerGap: CGFloat = 12

    /// Non-empty rounds, each with matches sorted top→bottom by bracket position.
    private var rounds: [WorldCupBracketRound] {
        bracket.rounds
            .filter { !$0.matches.isEmpty }
            .map { round in
                var r = round
                r.matches = round.matches.sorted { $0.bracketPosition < $1.bracketPosition }
                return r
            }
    }

    /// Constant column height; every round fills it so slots stay aligned.
    private var totalHeight: CGFloat {
        CGFloat(max(rounds.first?.matches.count ?? 1, 1)) * unitSlot
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: .appSpace2) {
                if usesProjections { legend }

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(rounds.enumerated()), id: \.offset) { index, round in
                        roundColumn(round)
                        if index < rounds.count - 1 {
                            connector(left: round.matches.count, right: rounds[index + 1].matches.count)
                        }
                    }

                    if let third = bracket.thirdPlacePlayoff {
                        Color.clear.frame(width: connectorWidth, height: totalHeight)
                        thirdPlaceColumn(third)
                    }
                }
            }
            .padding(.appSpace3)
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 10))
            Text("Italic teams are projected from current group standings")
                .font(.appCaption)
        }
        .foregroundStyle(Color.appInkFaint)
        .padding(.leading, .appSpace1)
    }

    // MARK: - Columns

    private func roundColumn(_ round: WorldCupBracketRound) -> some View {
        let slot = totalHeight / CGFloat(max(round.matches.count, 1))
        return VStack(spacing: headerGap) {
            Text(round.roundName.uppercased())
                .font(.appFootnote)
                .foregroundStyle(accent)
                .lineLimit(1)
                .frame(height: headerHeight, alignment: .bottom)
            VStack(spacing: 0) {
                ForEach(Array(round.matches.enumerated()), id: \.offset) { _, match in
                    cell(for: match)
                        .frame(width: cardWidth, height: slot)   // centers the card in its slot
                }
            }
            .frame(height: totalHeight)
        }
    }

    private func thirdPlaceColumn(_ match: WorldCupBracketMatch) -> some View {
        VStack(spacing: headerGap) {
            Text("THIRD PLACE")
                .font(.appFootnote)
                .foregroundStyle(accent)
                .frame(height: headerHeight, alignment: .bottom)
            VStack(spacing: 0) { cell(for: match) }
                .frame(width: cardWidth, height: totalHeight)
        }
    }

    /// Bracket elbows between a round of `left` cells and the next of `right`. Drawn
    /// only when the counts halve cleanly; otherwise just reserves the column gap.
    private func connector(left: Int, right: Int) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: headerHeight + headerGap)
            Group {
                if left > 0, right > 0, left == right * 2 {
                    Canvas { ctx, size in
                        let slotL = size.height / CGFloat(left)
                        let midX = size.width / 2
                        for j in 0..<right {
                            let aY = (CGFloat(2 * j) + 0.5) * slotL
                            let bY = (CGFloat(2 * j) + 1.5) * slotL
                            let tY = (aY + bY) / 2
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: aY)); path.addLine(to: CGPoint(x: midX, y: aY))
                            path.move(to: CGPoint(x: 0, y: bY)); path.addLine(to: CGPoint(x: midX, y: bY))
                            path.move(to: CGPoint(x: midX, y: aY)); path.addLine(to: CGPoint(x: midX, y: bY))
                            path.move(to: CGPoint(x: midX, y: tY)); path.addLine(to: CGPoint(x: size.width, y: tY))
                            ctx.stroke(path, with: .color(accent.opacity(0.4)), lineWidth: 1.5)
                        }
                    }
                    .frame(width: connectorWidth, height: totalHeight)
                } else {
                    Color.clear.frame(width: connectorWidth, height: totalHeight)
                }
            }
        }
    }

    // MARK: - Cells

    @ViewBuilder
    private func cell(for match: WorldCupBracketMatch) -> some View {
        let resolved = match.eventID.flatMap { viewModel.worldCupGameWithTeams(eventID: $0) }
        let cellView = WorldCupBracketMatchCell(model: cellModel(match, resolved: resolved), width: cardWidth, accent: accent)
        if let resolved, let home = resolved.homeTeam, let away = resolved.awayTeam {
            NavigationLink {
                AdaptiveGameDetail(game: resolved.game, homeTeam: home, awayTeam: away)
                    .environment(viewModel)
                    .environment(favorites)
            } label: {
                cellView
            }
            .buttonStyle(.plain)
        } else {
            cellView
        }
    }

    private func cellModel(_ match: WorldCupBracketMatch, resolved: GameWithTeams?) -> WorldCupBracketMatchCell.Model {
        let game = resolved?.game
        let homeProj = match.homeTeamName == nil ? projectedQualifier(match.homePlaceholder) : nil
        let awayProj = match.awayTeamName == nil ? projectedQualifier(match.awayPlaceholder) : nil

        let home = WorldCupBracketMatchCell.Side(
            name: match.homeTeamName ?? homeProj?.name ?? match.homePlaceholder ?? "TBD",
            badge: match.homeTeamBadge ?? homeProj?.badge,
            score: match.homeScore,
            isWinner: match.winner == .home,
            isResolved: match.homeTeamName != nil,
            isProjected: match.homeTeamName == nil && homeProj != nil
        )
        let away = WorldCupBracketMatchCell.Side(
            name: match.awayTeamName ?? awayProj?.name ?? match.awayPlaceholder ?? "TBD",
            badge: match.awayTeamBadge ?? awayProj?.badge,
            score: match.awayScore,
            isWinner: match.winner == .away,
            isResolved: match.awayTeamName != nil,
            isProjected: match.awayTeamName == nil && awayProj != nil
        )

        let isLive = game?.strStatus == "in"
        let isFinished = game?.strStatus == "post" || game?.isCompleted == true || match.winner != nil
        let kickoff = match.date ?? game?.standardDate

        let status: WorldCupBracketMatchCell.Status
        if isLive {
            status = .live(game?.strProgress ?? "LIVE")
        } else if isFinished {
            status = .final(match.aggregateScore)
        } else if let kickoff {
            status = .upcoming(kickoff)
        } else {
            status = .tbd
        }

        return WorldCupBracketMatchCell.Model(home: home, away: away, status: status, venue: game?.venueName)
    }

    // MARK: - Group → bracket projection

    private struct Qualifier { let name: String; let badge: String? }

    /// `"A" → [entries]`, ordered as ESPN returns them (top of the table first).
    private var groupTable: [String: [Entry]] {
        var table: [String: [Entry]] = [:]
        for child in groups {
            guard let letter = groupLetter(child.name),
                  let entries = child.standings?.entries, !entries.isEmpty else { continue }
            table[letter] = entries
        }
        return table
    }

    private var usesProjections: Bool {
        guard !groups.isEmpty else { return false }
        let all = rounds.flatMap { $0.matches } + (bracket.thirdPlacePlayoff.map { [$0] } ?? [])
        return all.contains { match in
            (match.homeTeamName == nil && projectedQualifier(match.homePlaceholder) != nil)
                || (match.awayTeamName == nil && projectedQualifier(match.awayPlaceholder) != nil)
        }
    }

    /// Resolves a placeholder like "Winner Group A" / "1A" to the nation currently
    /// sitting in that slot — but only once the group's matches are all played, so we
    /// never project a half-finished table.
    private func projectedQualifier(_ placeholder: String?) -> Qualifier? {
        guard let placeholder, !placeholder.isEmpty,
              let (letter, position) = parsePlaceholder(placeholder),
              groupIsFinal(letter),
              let entries = groupTable[letter], entries.count >= position else { return nil }
        let team = entries[position - 1].team
        guard let name = team?.shortDisplayName ?? team?.displayName else { return nil }
        return Qualifier(name: name, badge: team?.logos?.first?.href)
    }

    /// Extracts the group letter (A–L) and finishing position (1 or 2) from ESPN's
    /// slot text. Handles "Winner Group A", "Runner-up Group B", and "1A"/"2B" forms.
    private func parsePlaceholder(_ raw: String) -> (letter: String, position: Int)? {
        let s = raw.uppercased()
        var letter: String?
        var position: Int?

        if let range = s.range(of: "GROUP ") {
            if let c = s[range.upperBound...].drop(while: { $0 == " " }).first, ("A"..."L").contains(c) {
                letter = String(c)
            }
        }
        if s.contains("WINNER") { position = 1 } else if s.contains("RUNNER") { position = 2 }

        if letter == nil || position == nil {
            let chars = Array(s)
            for i in chars.indices where chars[i] == "1" || chars[i] == "2" {
                for n in [i - 1, i + 1] where chars.indices.contains(n) && ("A"..."L").contains(chars[n]) {
                    if position == nil { position = chars[i] == "1" ? 1 : 2 }
                    if letter == nil { letter = String(chars[n]) }
                }
            }
        }

        if let letter, let position { return (letter, position) }
        return nil
    }

    private func groupLetter(_ name: String?) -> String? {
        guard let last = name?.uppercased().split(separator: " ").last, last.count == 1,
              let c = last.first, ("A"..."L").contains(c) else { return nil }
        return String(c)
    }

    /// A group is "final" once every team has played its three group matches.
    private func groupIsFinal(_ letter: String) -> Bool {
        guard let entries = groupTable[letter], !entries.isEmpty else { return false }
        return entries.allSatisfy { gamesPlayed($0) >= 3 }
    }

    private func gamesPlayed(_ entry: Entry) -> Int {
        ["wins", "losses", "ties"].reduce(0) { $0 + statInt(entry, $1) }
    }

    private func statInt(_ entry: Entry, _ name: String) -> Int {
        guard let stat = entry.stats?.first(where: { $0.name == name }) else { return 0 }
        if let v = stat.value { return Int(v) }
        return Int(stat.displayValue ?? "") ?? 0
    }
}

/// Wraps `WorldCupBracketView` with the standard nav chrome and self-loads the
/// group standings (for projecting qualifiers into TBD slots), so any entry point —
/// the hub, the Games-tab hero, or the Browse pages — can deep-link straight to the
/// bracket with `WorldCupBracketScreen(bracket:)`. Requires `GameViewModel` and
/// `Favorites` in the environment (read by `WorldCupBracketView`).
struct WorldCupBracketScreen: View {
    let bracket: WorldCupBracket
    @State private var standings = WorldCupHeroStandings()

    var body: some View {
        WorldCupBracketView(bracket: bracket, groups: standings.groups)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Bracket")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .task { await standings.loadIfNeeded() }
    }
}

struct WorldCupBracketMatchCell: View {
    struct Side {
        var name: String
        var badge: String?
        var score: String?
        var isWinner: Bool
        var isResolved: Bool
        var isProjected: Bool
    }

    enum Status {
        case live(String)
        case final(String?)   // optional aggregate / penalties text
        case upcoming(Date)
        case tbd
    }

    struct Model {
        var home: Side
        var away: Side
        var status: Status
        var venue: String?
    }

    let model: Model
    var width: CGFloat = 196
    var accent: Color = .app(.soccer)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            statusRow
            sideRow(model.home)
            sideRow(model.away)
            if let venue = model.venue, !venue.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 9))
                    Text(venue).lineLimit(1)
                }
                .font(.appCaption)
                .foregroundStyle(Color.appInkFaint)
            }
        }
        .frame(width: width, alignment: .leading)
        .appCard(fill: Color.appAlt)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch model.status {
        case .live(let period):
            LiveTag(period: period)
        case .final(let aggregate):
            HStack(spacing: 6) {
                Text("FULL TIME").font(.appFootnote).foregroundStyle(Color.appInkFaint)
                if let aggregate, !aggregate.isEmpty {
                    Text(aggregate).font(.appCaption).foregroundStyle(accent)
                }
            }
        case .upcoming(let date):
            Text(Self.dateFormatter.string(from: date))
                .font(.appCaption)
                .foregroundStyle(Color.appInkFaint)
        case .tbd:
            Text("TBD").font(.appCaption).foregroundStyle(Color.appInkFaint)
        }
    }

    private func sideRow(_ side: Side) -> some View {
        HStack(spacing: .appSpace2) {
            WCBadge(url: side.badge, size: 22)
            Text(side.name)
                .font(.appCallout)
                .fontWeight(side.isWinner ? .bold : .regular)
                .italic(side.isProjected)
                .foregroundStyle(color(for: side))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let score = side.score, !score.isEmpty {
                Text(score)
                    .font(.appCallout)
                    .fontWeight(side.isWinner ? .bold : .regular)
                    .foregroundStyle(side.isWinner ? accent : Color.appInk)
            }
        }
    }

    private func color(for side: Side) -> Color {
        if side.isProjected { return Color.appInkSoft }
        if !side.isResolved { return Color.appInkFaint }
        return side.isWinner ? accent : Color.appInk
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f
    }()
}

#if DEBUG
private enum WCBracketMock {
    static let wcID = String(Leagues.FIFA_World_Cup.rawValue)

    static func game(_ home: String, _ away: String, homeScore: String? = nil, awayScore: String? = nil,
                     status: String, progress: String? = nil, offsetMinutes: Int, id: String) -> Game {
        Game(
            idEvent: id,
            idLeague: wcID,
            strHomeTeam: home,
            strAwayTeam: away,
            intHomeScore: homeScore,
            intAwayScore: awayScore,
            strStatus: status,
            strProgress: progress,
            isoDate: Date().addingTimeInterval(TimeInterval(offsetMinutes * 60))
        )
    }

    static func standings() -> [Child] {
        func stat(_ name: String, _ value: Int) -> Stat {
            Stat(name: name, displayName: nil, shortDisplayName: nil, description: nil,
                 abbreviation: nil, type: nil, value: Double(value), displayValue: "\(value)",
                 id: nil, summary: nil)
        }
        // All teams have played 3 (group is final) so qualifiers project.
        func entry(_ abbr: String, _ name: String, w: Int, l: Int, d: Int, pts: Int) -> Entry {
            let team = ESPNTeam(id: abbr, uid: nil, slug: nil, abbreviation: abbr,
                                displayName: name, shortDisplayName: abbr, name: name, nickname: nil,
                                location: nil, color: nil, alternateColor: nil,
                                isActive: true, isAllStar: false, logos: nil, links: nil)
            return Entry(team: team, note: nil,
                         stats: [stat("wins", w), stat("losses", l), stat("ties", d), stat("points", pts)])
        }
        func group(_ letter: String, _ entries: [Entry]) -> Child {
            Child(uid: nil, id: letter, name: "Group \(letter)", abbreviation: letter,
                  standings: Standings(id: nil, name: nil, displayName: nil, links: nil,
                                       season: nil, seasonType: nil, entries: entries))
        }
        return [
            group("A", [entry("MEX", "Mexico", w: 3, l: 0, d: 0, pts: 9),
                        entry("CZE", "Czechia", w: 2, l: 1, d: 0, pts: 6),
                        entry("KOR", "South Korea", w: 1, l: 2, d: 0, pts: 3),
                        entry("RSA", "South Africa", w: 0, l: 3, d: 0, pts: 0)]),
            group("B", [entry("CAN", "Canada", w: 2, l: 0, d: 1, pts: 7),
                        entry("SUI", "Switzerland", w: 1, l: 0, d: 2, pts: 5),
                        entry("BIH", "Bosnia", w: 1, l: 2, d: 0, pts: 3),
                        entry("QAT", "Qatar", w: 0, l: 2, d: 1, pts: 1)]),
        ]
    }

    @MainActor
    static func harness() -> some View {
        GameViewModel.isSnapshotTesting = true
        let storage = UserDefaultStorage()
        let favorites = Favorites()

        let games = [
            game("Mexico", "Brazil", homeScore: "1", awayScore: "2", status: "in", progress: "67'", offsetMinutes: -67, id: "qf-1"),
            game("Argentina", "France", homeScore: "3", awayScore: "1", status: "post", progress: "FT", offsetMinutes: -180, id: "qf-2"),
        ]
        let viewModel = GameViewModel(appStorage: storage, favorites: favorites, totalGames: games)

        func match(_ id: String?, _ home: String?, _ away: String?, hs: String? = nil, aScore: String? = nil,
                   winner: BracketSide? = nil, hp: String? = nil, ap: String? = nil, pos: Int, offset: Int? = nil) -> WorldCupBracketMatch {
            WorldCupBracketMatch(eventID: id, homeTeamName: home, awayTeamName: away,
                                 homeScore: hs, awayScore: aScore, winner: winner,
                                 date: offset.map { Date().addingTimeInterval(TimeInterval($0 * 60)) },
                                 homePlaceholder: hp, awayPlaceholder: ap, bracketPosition: pos)
        }

        let bracket = WorldCupBracket(rounds: [
            WorldCupBracketRound(roundName: "Quarterfinals", slug: "qf", matches: [
                match("qf-1", "Mexico", "Brazil", hs: "1", aScore: "2", pos: 0),
                match("qf-2", "Argentina", "France", hs: "3", aScore: "1", winner: .home, pos: 1),
                match(nil, nil, nil, hp: "Winner Group A", ap: "Runner-up Group B", pos: 2),
                match(nil, nil, nil, hp: "Winner Group B", ap: "Runner-up Group A", pos: 3),
            ]),
            WorldCupBracketRound(roundName: "Semifinals", slug: "sf", matches: [
                match(nil, nil, nil, hp: "Winner QF1", ap: "Winner QF2", pos: 0, offset: 2880),
                match(nil, nil, nil, hp: "Winner QF3", ap: "Winner QF4", pos: 1, offset: 2880),
            ]),
            WorldCupBracketRound(roundName: "Final", slug: "final", matches: [
                match(nil, nil, nil, hp: "Winner SF1", ap: "Winner SF2", pos: 0, offset: 5760),
            ]),
        ], thirdPlacePlayoff: match(nil, nil, nil, hp: "Loser SF1", ap: "Loser SF2", pos: 0, offset: 5700))

        return NavigationStack {
            WorldCupBracketView(bracket: bracket, groups: standings())
                .background(Color.appBackground.ignoresSafeArea())
                .navigationTitle("Bracket")
        }
        .environment(viewModel)
        .environment(storage)
        .environment(favorites)
        .preferredColorScheme(.dark)
    }
}

#Preview("Bracket") {
    WCBracketMock.harness()
}
#endif
