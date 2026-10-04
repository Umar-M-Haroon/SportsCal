//
//  SoccerMatchCentreView.swift
//  SportsCal
//
//  The soccer match centre, shown inside the game detail stack for every soccer
//  league: the goal/card/sub timeline, lineups (on a pitch, or as a list), the
//  team stat comparison with estimated xG, each side's recent form, the
//  head-to-head record, and live commentary. Data is fetched on demand from
//  `/soccer/match/:eventID` (see GameDetailSectionsModel.loadSoccerMatch).
//
//  Layout follows the rest of GameDetailView: away on the left, home on the right.
//  `style` switches the card chrome between the Classic and Modern detail screens.
//

import SwiftUI
import SportsCalModel

struct SoccerMatchCentreView: View {
    enum Style { case classic, modern }

    let match: SoccerMatchDetail
    let game: Game
    var style: Style = .classic

    @State private var lineupMode: LineupMode = .pitch
    @State private var showsAllCommentary = false
    /// Set from the pitch's player popover, which sits outside the navigation stack.
    @State private var profilePlayer: SoccerLineupPlayer?

    private enum LineupMode: String, CaseIterable, Identifiable {
        case pitch = "Pitch"
        case list = "List"
        var id: String { rawValue }
    }

    private var awayColor: Color { Color(hex: game.awayTeamColor ?? "") ?? .accentColor }
    private var homeColor: Color { Color(hex: game.homeTeamColor ?? "") ?? .secondary }

    private var spacing: CGFloat { style == .modern ? .appSpace5 : 24 }

    var body: some View {
        VStack(spacing: spacing) {
            if !match.events.isEmpty {
                eventsCard
            }
            if !match.momentum.isEmpty {
                momentumCard
            }
            if !match.home.players.isEmpty || !match.away.players.isEmpty {
                lineupsCard
            }
            if !displayedTeamStats.isEmpty {
                teamStatsCard
            }
            if !match.shots.isEmpty {
                shotMapCard
            }
            if !match.home.form.isEmpty || !match.away.form.isEmpty {
                formCard
            }
            if let headToHead = match.headToHead, !headToHead.matches.isEmpty {
                headToHeadCard(headToHead)
            }
            if !match.commentary.isEmpty {
                commentaryCard
            }
        }
        .navigationDestination(item: $profilePlayer) { player in
            SoccerPlayerView(athleteID: player.athleteID ?? "", name: player.name)
        }
    }

    // MARK: - Card chrome

    @ViewBuilder
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        switch style {
        case .classic:
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        case .modern:
            VStack(alignment: .leading, spacing: .appSpace3) {
                Text(title.uppercased()).appEyebrow().foregroundStyle(Color.app(.soccer))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
        }
    }

    // MARK: - Match events timeline

    private var eventsCard: some View {
        card("Match Events") {
            VStack(spacing: 10) {
                ForEach(match.events) { event in
                    eventRow(event)
                }
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: SoccerMatchEvent) -> some View {
        let isHome = event.side == .home
        HStack(alignment: .top, spacing: 8) {
            // Away column (left)
            Group {
                if !isHome { eventDetail(event, alignment: .leading) }
                else { Color.clear.frame(height: 1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Minute + icon spine
            VStack(spacing: 2) {
                Image(systemName: eventIcon(event.type))
                    .font(.caption)
                    .foregroundStyle(eventTint(event.type, isHome: isHome))
                if let clock = event.clock {
                    Text(clock)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(width: 44)

            // Home column (right)
            Group {
                if isHome { eventDetail(event, alignment: .trailing) }
                else { Color.clear.frame(height: 1) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func eventDetail(_ event: SoccerMatchEvent, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(eventPrimaryText(event))
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                .lineLimit(2)
            if let secondary = eventSecondaryText(event) {
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func eventPrimaryText(_ event: SoccerMatchEvent) -> String {
        switch event.type {
        case .goal, .penaltyGoal, .ownGoal:
            let scorer = event.playerNames.first ?? event.shortText ?? "Goal"
            return event.type == .ownGoal ? "\(scorer) (OG)" : scorer
        case .substitution:
            if let inName = event.playerNames.first { return inName }
            return event.shortText ?? "Substitution"
        case .yellowCard, .redCard:
            return event.playerNames.first ?? event.shortText ?? event.typeText
        default:
            return event.shortText ?? event.typeText
        }
    }

    private func eventSecondaryText(_ event: SoccerMatchEvent) -> String? {
        switch event.type {
        case .goal, .penaltyGoal:
            if event.playerNames.count > 1 { return "assist: \(event.playerNames[1])" }
            return event.type == .penaltyGoal ? "Penalty" : nil
        case .substitution:
            if event.playerNames.count > 1 { return "out: \(event.playerNames[1])" }
            // Participants are often absent on subs — surface ESPN's narration instead.
            if event.playerNames.isEmpty, let text = event.text {
                return text.replacingOccurrences(of: "Substitution, ", with: "")
            }
            return nil
        default:
            return nil
        }
    }

    private func eventIcon(_ type: SoccerMatchEventType) -> String {
        switch type {
        case .goal, .penaltyGoal, .ownGoal: return "soccerball"
        case .penaltyMissed: return "xmark.circle"
        case .yellowCard, .redCard: return "rectangle.portrait.fill"
        case .substitution: return "arrow.left.arrow.right"
        case .other: return "circle.fill"
        }
    }

    private func eventTint(_ type: SoccerMatchEventType, isHome: Bool) -> Color {
        switch type {
        case .yellowCard: return .yellow
        case .redCard: return .red
        case .substitution: return .secondary
        case .goal, .penaltyGoal, .ownGoal: return isHome ? homeColor : awayColor
        default: return .secondary
        }
    }

    // MARK: - Momentum and shot map

    private var homeName: String { match.home.teamName.isEmpty ? game.strHomeTeam : match.home.teamName }
    private var awayName: String { match.away.teamName.isEmpty ? game.strAwayTeam : match.away.teamName }

    private var momentumCard: some View {
        card("Momentum") {
            SoccerMomentumView(
                momentum: match.momentum, shots: match.shots,
                homeName: homeName, awayName: awayName,
                homeColor: homeColor, awayColor: awayColor
            )
        }
    }

    private var shotMapCard: some View {
        card("Shot Map") {
            SoccerShotMapView(
                shots: match.shots,
                homeName: homeName, awayName: awayName,
                homeColor: homeColor, awayColor: awayColor
            )
        }
    }

    // MARK: - Lineups

    private var pitchAvailable: Bool {
        SoccerFormationLayout.place(match.home) != nil && SoccerFormationLayout.place(match.away) != nil
    }

    private var lineupsCard: some View {
        card("Lineups") {
            if pitchAvailable {
                Picker("Lineup style", selection: $lineupMode) {
                    ForEach(LineupMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if pitchAvailable && lineupMode == .pitch {
                SoccerPitchView(
                    home: match.home, away: match.away,
                    homeColor: homeColor, awayColor: awayColor,
                    onOpenProfile: { profilePlayer = $0 }
                )
                substitutesColumns
            } else {
                teamLineup(match.away, accent: awayColor, fallbackName: game.strAwayTeam)
                Divider()
                teamLineup(match.home, accent: homeColor, fallbackName: game.strHomeTeam)
            }
        }
    }

    /// A player row that opens their profile, when ESPN gave us their id.
    @ViewBuilder
    private func linkedToProfile<Content: View>(_ player: SoccerLineupPlayer, @ViewBuilder content: () -> Content) -> some View {
        if let athleteID = player.athleteID {
            let row = content()
            SoccerPlayerLink(athleteID: athleteID, name: player.name) { row.contentShape(Rectangle()) }
        } else {
            content()
        }
    }

    /// Both benches side by side under the pitch: away left, home right.
    private var substitutesColumns: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Substitutes")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                benchColumn(match.away)
                benchColumn(match.home)
            }
        }
        .padding(.top, 4)
    }

    private func benchColumn(_ team: SoccerLineup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Players who came on first, then the unused bench.
            let bench = team.substitutes.sorted { $0.subbedIn && !$1.subbedIn }
            ForEach(bench) { player in
                linkedToProfile(player) {
                    HStack(spacing: 6) {
                        Text(player.jersey ?? "–")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 18, alignment: .trailing)
                        Text(player.name)
                            .font(.caption)
                            .foregroundStyle(player.subbedIn ? .primary : .secondary)
                            .lineLimit(1)
                        if player.subbedIn {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green.opacity(0.8))
                        }
                        ForEach(notableBadges(player.stats), id: \.self) { badge in
                            Text(badge).font(.caption2)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func teamLineup(_ team: SoccerLineup, accent: Color, fallbackName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(team.teamName.isEmpty ? fallbackName : team.teamName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let formation = team.formation, !formation.isEmpty {
                    Text(formation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            ForEach(team.starters) { player in
                linkedToProfile(player) { playerRow(player, accent: accent) }
            }

            if !team.substitutes.isEmpty {
                Text("Substitutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(team.substitutes) { player in
                    linkedToProfile(player) { playerRow(player, accent: accent) }
                }
            }
        }
    }

    @ViewBuilder
    private func playerRow(_ player: SoccerLineupPlayer, accent: Color) -> some View {
        HStack(spacing: 10) {
            Text(player.jersey ?? "–")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(player.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    if player.subbedOut {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    if player.subbedIn {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green.opacity(0.7))
                    }
                }
                if let pos = player.positionName ?? player.position, !pos.isEmpty {
                    Text(pos)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                ForEach(notableBadges(player.stats), id: \.self) { badge in
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
            }
        }
    }

    /// Compact glyphs for the stats worth surfacing inline next to a player.
    private func notableBadges(_ stats: [SoccerPlayerStat]) -> [String] {
        var badges: [String] = []
        for stat in stats {
            guard let value = stat.value, value > 0 else { continue }
            let count = Int(value)
            switch stat.name {
            case "totalGoals": badges.append(String(repeating: "⚽︎", count: max(count, 1)))
            case "ownGoals": badges.append("OG")
            case "goalAssists": badges.append("🅰︎\(count > 1 ? "×\(count)" : "")")
            case "yellowCards": badges.append("🟨")
            case "redCards": badges.append("🟥")
            default: break
            }
        }
        return badges
    }

    // MARK: - Team stat comparison

    /// ESPN's stats, led by our estimated xG when the match has located shots.
    private var displayedTeamStats: [SoccerTeamStat] {
        guard !match.shots.isEmpty else { return match.teamStats }
        let home = match.expectedGoals(.home)
        let away = match.expectedGoals(.away)
        let xG = SoccerTeamStat(
            name: "xG", label: "xG (est.)",
            homeDisplay: String(format: "%.2f", home), awayDisplay: String(format: "%.2f", away),
            homeValue: home, awayValue: away
        )
        return [xG] + match.teamStats
    }

    private var teamStatsCard: some View {
        card("Team Stats") {
            VStack(spacing: 14) {
                ForEach(displayedTeamStats) { stat in
                    teamStatRow(stat)
                }
            }
        }
    }

    @ViewBuilder
    private func teamStatRow(_ stat: SoccerTeamStat) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(stat.awayDisplay)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Spacer()
                Text(stat.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(stat.homeDisplay)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            comparisonBar(home: stat.homeValue, away: stat.awayValue)
        }
    }

    @ViewBuilder
    private func comparisonBar(home: Double?, away: Double?) -> some View {
        let h = max(home ?? 0, 0)
        let a = max(away ?? 0, 0)
        let total = h + a
        GeometryReader { geo in
            HStack(spacing: 2) {
                Capsule()
                    .fill(awayColor)
                    .frame(width: total > 0 ? geo.size.width * CGFloat(a / total) : geo.size.width / 2)
                Capsule()
                    .fill(homeColor)
            }
        }
        .frame(height: 5)
    }

    // MARK: - Form

    private var formCard: some View {
        card("Form") {
            VStack(spacing: 12) {
                formRow(match.away, fallbackName: game.strAwayTeam)
                formRow(match.home, fallbackName: game.strHomeTeam)
            }
            Text("Last five matches, most recent on the right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formRow(_ team: SoccerLineup, fallbackName: String) -> some View {
        HStack(spacing: 8) {
            Text(team.teamName.isEmpty ? fallbackName : team.teamName)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 8)
            ForEach(team.form) { result in
                VStack(spacing: 2) {
                    Text(result.result.rawValue)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 22)
                        .background(resultColor(result.result), in: RoundedRectangle(cornerRadius: 5))
                    Text("\(result.goalsFor)-\(result.goalsAgainst)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(formAccessibilityLabel(result))
            }
        }
    }

    private func resultColor(_ result: SoccerResult) -> Color {
        switch result {
        case .win: return .green
        case .draw: return .gray
        case .loss: return .red
        }
    }

    private func formAccessibilityLabel(_ result: SoccerFormMatch) -> String {
        let outcome = switch result.result {
        case .win: "Won"
        case .draw: "Drew"
        case .loss: "Lost"
        }
        let venue = result.isHome ? "at home to" : "away at"
        return "\(outcome) \(result.goalsFor)–\(result.goalsAgainst) \(venue) \(result.opponentName)"
    }

    // MARK: - Head-to-head

    private func headToHeadCard(_ headToHead: SoccerHeadToHead) -> some View {
        card("Head-to-Head") {
            if let summary = headToHead.summary {
                Text(summary)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            VStack(spacing: 8) {
                ForEach(headToHead.matches.prefix(5)) { meeting in
                    meetingRow(meeting)
                }
            }
        }
    }

    private func meetingRow(_ meeting: SoccerPastMeeting) -> some View {
        HStack(spacing: 8) {
            Text(meeting.date.map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(meeting.homeAbbreviation ?? meeting.homeName)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1)
            Text(meetingScore(meeting))
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(width: 44)
            Text(meeting.awayAbbreviation ?? meeting.awayName)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
    }

    private func meetingScore(_ meeting: SoccerPastMeeting) -> String {
        guard let home = meeting.homeScore, let away = meeting.awayScore else { return "v" }
        return "\(home)–\(away)"
    }

    // MARK: - Commentary

    private static let collapsedCommentaryCount = 6

    private var commentaryCard: some View {
        // Newest first, like a live feed.
        let entries = Array(match.commentary.reversed())
        let visible = showsAllCommentary ? entries : Array(entries.prefix(Self.collapsedCommentaryCount))
        return card("Commentary") {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(visible) { entry in
                    commentaryRow(entry)
                }
            }
            if entries.count > Self.collapsedCommentaryCount {
                Button(showsAllCommentary ? "Show less" : "Show all \(entries.count) updates") {
                    withAnimation(.snappy) { showsAllCommentary.toggle() }
                }
                .font(.subheadline)
            }
        }
    }

    private func commentaryRow(_ entry: SoccerCommentaryEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.clock ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
            Group {
                if let icon = commentaryIcon(entry.kind) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(commentaryTint(entry))
                }
            }
            .frame(width: 16)
            Text(entry.text)
                .font(.subheadline)
                .fontWeight(entry.kind == .goal ? .semibold : .regular)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func commentaryIcon(_ kind: SoccerCommentaryKind) -> String? {
        switch kind {
        case .goal: return "soccerball"
        case .chance: return "scope"
        case .card: return "rectangle.portrait.fill"
        case .substitution: return "arrow.left.arrow.right"
        case .var: return "tv"
        case .periodBoundary: return "clock"
        case .other: return nil
        }
    }

    private func commentaryTint(_ entry: SoccerCommentaryEntry) -> Color {
        switch entry.kind {
        case .card: return entry.text.localizedCaseInsensitiveContains("red card") ? .red : .yellow
        case .goal: return entry.side == .home ? homeColor : awayColor
        default: return .secondary
        }
    }
}
