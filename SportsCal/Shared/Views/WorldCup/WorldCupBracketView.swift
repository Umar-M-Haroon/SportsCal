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
        let layout = bracketLayout
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: .appSpace2) {
                if usesProjections { legend }

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(rounds.enumerated()), id: \.offset) { index, round in
                        roundColumn(round, displayOrder: layout.orders[index])
                        if index < rounds.count - 1 {
                            Color.clear.frame(width: connectorWidth,
                                              height: headerHeight + headerGap + totalHeight)
                        }
                    }

                    if let third = bracket.thirdPlacePlayoff {
                        Color.clear.frame(width: connectorWidth, height: totalHeight)
                        thirdPlaceColumn(third)
                    }
                }
                // Connectors render behind the cards (background), so elbows never
                // draw over card chrome even where they touch the card edges.
                .background(alignment: .topLeading) {
                    connectorCanvas(links: layout.links)
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

    /// `displayOrder` maps top→bottom display slots to chronological match indices,
    /// so each match sits beside the next-round slot its winner actually feeds.
    private func roundColumn(_ round: WorldCupBracketRound, displayOrder: [Int]) -> some View {
        let slot = totalHeight / CGFloat(max(round.matches.count, 1))
        return VStack(spacing: headerGap) {
            Text(round.roundName.uppercased())
                .font(.appFootnote)
                .foregroundStyle(accent)
                .lineLimit(1)
                .frame(height: headerHeight, alignment: .bottom)
            VStack(spacing: 0) {
                ForEach(displayOrder, id: \.self) { chronoIndex in
                    cell(for: round.matches[chronoIndex], number: chronoIndex + 1)
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

    // MARK: - Progression topology
    //
    // ESPN encodes progression, not us: an undecided slot's "team name" is literally
    // "Round of 32 11 Winner", where 11 is the 1-based *chronological* match number
    // within the feeder round; a decided slot carries the winning nation's name. From
    // those two signals we recover which match feeds which slot, then lay each round
    // out top→bottom so feeders sit beside the slot they flow into and elbows never
    // cross. Chronological order (the server's `bracketPosition`) stays the source of
    // the display numbers so "Game 11" here matches "Round of 32 11 Winner" there.

    private struct Feeders { var home: Int?; var away: Int? }

    /// One entry per displayed slot: which chronological match in the previous round
    /// feeds each side of this match. Index 0 (first round) has no feeders.
    private func feederMap(_ rounds: [WorldCupBracketRound]) -> [[Feeders]] {
        rounds.indices.map { r in
            guard r > 0 else { return rounds[r].matches.map { _ in Feeders() } }
            let prev = rounds[r - 1]
            return rounds[r].matches.map { match in
                Feeders(
                    home: feederIndex(name: match.homeTeamName, placeholder: match.homePlaceholder, in: prev),
                    away: feederIndex(name: match.awayTeamName, placeholder: match.awayPlaceholder, in: prev)
                )
            }
        }
    }

    private func feederIndex(name: String?, placeholder: String?, in prev: WorldCupBracketRound) -> Int? {
        if let n = referencedMatchNumber(name ?? placeholder, roundSize: prev.matches.count) { return n }
        return participantIndex(ofTeamNamed: name, in: prev)
    }

    /// Parses "Round of 32 11 Winner" (or any "… N winner" variant) → chronological
    /// index N-1. The round name itself contains digits ("Round of 32"), so the game
    /// reference is the LAST number, validated against the feeder round's size. Group
    /// placeholders ("Winner Group A") carry no usable digits and return nil.
    private func referencedMatchNumber(_ text: String?, roundSize: Int) -> Int? {
        guard let lower = text?.lowercased(), lower.contains("winner") else { return nil }
        let numbers = lower.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let n = numbers.last, n >= 1, n <= roundSize else { return nil }
        return n - 1
    }

    /// Finds the previous-round match this nation played in, for slots ESPN has
    /// resolved. Participation — not the server-derived `winner`, which stays nil for
    /// penalty-shootout wins and mid-live snapshots even after ESPN advances the
    /// nation — is what links a slot to its feeder; a nation plays once per round.
    private func participantIndex(ofTeamNamed name: String?, in round: WorldCupBracketRound) -> Int? {
        guard let name, !name.isEmpty, !isPlaceholderName(name) else { return nil }
        return round.matches.firstIndex { match in
            match.homeTeamName?.caseInsensitiveCompare(name) == .orderedSame ||
            match.awayTeamName?.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Display order per round plus the connector links between adjacent rounds.
    /// `orders[r]` lists chronological indices top→bottom; `links[r]` connects display
    /// slots of round r to display slots of round r+1.
    private var bracketLayout: (orders: [[Int]], links: [[(from: Int, to: Int)]]) {
        let rounds = self.rounds
        var orders: [[Int]] = rounds.map { Array($0.matches.indices) }
        guard rounds.count > 1 else { return (orders, []) }
        let feeders = feederMap(rounds)

        // Later rounds fix the tree: walk from the last round down, placing each
        // slot's feeders adjacent beneath it. Unreferenced matches keep date order.
        for r in stride(from: rounds.count - 2, through: 0, by: -1) {
            var placed = Set<Int>()
            var order: [Int] = []
            for target in orders[r + 1] {
                for feeder in [feeders[r + 1][target].home, feeders[r + 1][target].away] {
                    if let feeder, placed.insert(feeder).inserted { order.append(feeder) }
                }
            }
            for i in rounds[r].matches.indices where !placed.contains(i) { order.append(i) }
            orders[r] = order
        }

        let links: [[(from: Int, to: Int)]] = (0..<(rounds.count - 1)).map { r in
            var out: [(Int, Int)] = []
            for (targetPos, target) in orders[r + 1].enumerated() {
                for feeder in [feeders[r + 1][target].home, feeders[r + 1][target].away] {
                    if let feeder, let feederPos = orders[r].firstIndex(of: feeder) {
                        out.append((feederPos, targetPos))
                    }
                }
            }
            return out
        }
        return (orders, links)
    }

    /// All bracket elbows in one layer, drawn in the HStack's coordinate space so the
    /// lines sit behind every card. `links[r]` joins display slots of rounds r and r+1.
    private func connectorCanvas(links: [[(from: Int, to: Int)]]) -> some View {
        let rounds = self.rounds
        let yOffset = headerHeight + headerGap
        return Canvas { ctx, _ in
            for r in links.indices {
                let slotL = totalHeight / CGFloat(max(rounds[r].matches.count, 1))
                let slotR = totalHeight / CGFloat(max(rounds[r + 1].matches.count, 1))
                let cardRight = CGFloat(r) * (cardWidth + connectorWidth) + cardWidth
                let nextCardLeft = cardRight + connectorWidth
                let midX = cardRight + connectorWidth / 2
                for link in links[r] {
                    let fromY = yOffset + slotL * (CGFloat(link.from) + 0.5)
                    let toY = yOffset + slotR * (CGFloat(link.to) + 0.5)
                    var path = Path()
                    path.move(to: CGPoint(x: cardRight, y: fromY))
                    path.addLine(to: CGPoint(x: midX, y: fromY))
                    path.addLine(to: CGPoint(x: midX, y: toY))
                    path.addLine(to: CGPoint(x: nextCardLeft, y: toY))
                    ctx.stroke(path, with: .color(accent.opacity(0.4)), lineWidth: 1.5)
                }
            }
        }
    }

    // MARK: - Cells

    @ViewBuilder
    private func cell(for match: WorldCupBracketMatch, number: Int? = nil) -> some View {
        let resolved = match.eventID.flatMap { viewModel.worldCupGameWithTeams(eventID: $0) }
        let cellView = WorldCupBracketMatchCell(model: cellModel(match, resolved: resolved, number: number), width: cardWidth, accent: accent)
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

    /// ESPN ships undecided slots as pseudo team names ("Round of 32 11 Winner",
    /// "Winner Group A"); treat those as placeholders, not resolved nations.
    private func isPlaceholderName(_ name: String?) -> Bool {
        guard let lower = name?.lowercased(), !lower.isEmpty else { return false }
        return lower == "tbd" || lower.contains("winner") || lower.contains("runner") || lower.contains("loser")
    }

    /// Shortens "Round of 32 11 Winner" to "Game 11 Winner" so it reads against the
    /// "Game 11" chip on the feeder card one column to the left.
    private func friendlyPlaceholder(_ text: String?, previousRoundSize: Int) -> String? {
        guard let text else { return nil }
        if let index = referencedMatchNumber(text, roundSize: previousRoundSize) {
            return "Game \(index + 1) Winner"
        }
        return text
    }

    private func cellModel(_ match: WorldCupBracketMatch, resolved: GameWithTeams?, number: Int?) -> WorldCupBracketMatchCell.Model {
        let game = resolved?.game
        let homeName = isPlaceholderName(match.homeTeamName) ? nil : match.homeTeamName
        let awayName = isPlaceholderName(match.awayTeamName) ? nil : match.awayTeamName
        let homePlaceholder = match.homePlaceholder ?? (homeName == nil ? match.homeTeamName : nil)
        let awayPlaceholder = match.awayPlaceholder ?? (awayName == nil ? match.awayTeamName : nil)
        let previousRoundSize = previousRoundSize(for: match)
        let homeProj = homeName == nil ? projectedQualifier(homePlaceholder) : nil
        let awayProj = awayName == nil ? projectedQualifier(awayPlaceholder) : nil

        let home = WorldCupBracketMatchCell.Side(
            name: homeName ?? homeProj?.name ?? friendlyPlaceholder(homePlaceholder, previousRoundSize: previousRoundSize) ?? "TBD",
            badge: match.homeTeamBadge ?? homeProj?.badge,
            score: match.homeScore,
            isWinner: match.winner == .home,
            isResolved: homeName != nil,
            isProjected: homeName == nil && homeProj != nil
        )
        let away = WorldCupBracketMatchCell.Side(
            name: awayName ?? awayProj?.name ?? friendlyPlaceholder(awayPlaceholder, previousRoundSize: previousRoundSize) ?? "TBD",
            badge: match.awayTeamBadge ?? awayProj?.badge,
            score: match.awayScore,
            isWinner: match.winner == .away,
            isResolved: awayName != nil,
            isProjected: awayName == nil && awayProj != nil
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

        return WorldCupBracketMatchCell.Model(home: home, away: away, status: status, venue: game?.venueName, number: number)
    }

    /// Size of the round feeding this match's round (bounds-checks placeholder
    /// references); 0 for the first round, where slots reference groups instead.
    private func previousRoundSize(for match: WorldCupBracketMatch) -> Int {
        guard let r = rounds.firstIndex(where: { $0.matches.contains(match) }), r > 0 else {
            // Third-place playoff and unknown matches: allow any plausible reference.
            return Int.max
        }
        return rounds[r - 1].matches.count
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
            let homeOpen = match.homeTeamName == nil || isPlaceholderName(match.homeTeamName)
            let awayOpen = match.awayTeamName == nil || isPlaceholderName(match.awayTeamName)
            return (homeOpen && projectedQualifier(match.homePlaceholder ?? match.homeTeamName) != nil)
                || (awayOpen && projectedQualifier(match.awayPlaceholder ?? match.awayTeamName) != nil)
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
        /// Chronological match number within its round ("Game 11") — the same number
        /// later rounds use to reference this match, so progression is traceable.
        var number: Int?
    }

    let model: Model
    var width: CGFloat = 196
    var accent: Color = .app(.soccer)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                statusRow
                if let number = model.number {
                    Spacer(minLength: 4)
                    Text("Game \(number)")
                        .font(.appCaption)
                        .foregroundStyle(Color.appInkFaint)
                }
            }
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
