//
//  LiveSportActivityWidget.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/28/22.
//

// ActivityKit/Dynamic Island are iOS-only; the bare UIKit import below would
// otherwise break the native-macOS widget build.
#if os(iOS)
import SwiftUI
import WidgetKit
import UIKit
import SportsCalModel
#if canImport(ActivityKit)

/// Loads a team badge image from the shared app group container, with a fallback to team initials.
/// Used by the lock screen and expanded Dynamic Island where raster images render in full color.
@ViewBuilder
private func badgeImage(for teamName: String, code: String? = nil, size: CGFloat) -> some View {
    if let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(teamName),
       let data = try? Data(contentsOf: fileURL),
       let image = UIImage(data: data) {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    } else {
        teamInitialsView(teamName, code: code, size: size)
    }
}

/// Compact-friendly team identifier for Dynamic Island compact and minimal slots,
/// where Apple's tinting flattens raster logos. Prefers the explicit short field
/// from the activity attributes (the team's `strTeamShort`, e.g. "PHI", "NYY")
/// and falls back to the first 3 characters of the full name for activities
/// started before the field existed or via server push-to-start without it.
private func shortAbbreviation(short: String?, full: String) -> String {
    return Team.shortCode(strTeamShort: short, name: full)
}

/// Fallback view showing team initials in a circle when badge image is unavailable.
/// Uses a high-contrast white-bordered circle so it stays visible against the
/// Dynamic Island's black background — the previous `WidgetTokens.alt` fill was
/// nearly invisible there, making missing badges look like nothing rendered.
@ViewBuilder
private func teamInitialsView(_ teamName: String, code: String? = nil, size: CGFloat) -> some View {
    ZStack {
        Circle()
            .fill(.white.opacity(0.18))
            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
            .frame(width: size, height: size)
        Text(Team.shortCode(strTeamShort: code, name: teamName))
            .font(.system(size: size * 0.35, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
    }
}

// MARK: - Live Activity state inference (no schema migration)

/// Derives a more nuanced state from the existing ContentState fields.
/// Lets the widget render distinct halftime / final variants without
/// growing the Codable schema (which would break active activities).
enum LiveActivityVariant {
    case live, halftime, final
    /// A scheduled stop inside the game: a hockey intermission, MLB's "Mid 5th" / "End 5th".
    case intermission
    /// Play isn't running and won't on a schedule: delayed, postponed, suspended.
    case stopped
}

private func variantFor(progress: String?, status: String?) -> LiveActivityVariant {
    let p = (progress ?? "").lowercased().trimmingCharacters(in: .whitespaces)
    let s = (status ?? "").lowercased().trimmingCharacters(in: .whitespaces)
    // A suspended game is "post" but not over: it resumes another day.
    if p.hasPrefix("suspended") {
        return .stopped
    }
    // ESPN state "post", soccer FT / AET / penalties, TheSportsDB codes, "Final/OT".
    let finalStatuses: Set<String> = ["post", "ft", "aet", "ap", "pen", "pens", "final", "match finished"]
    let finalProgress: Set<String> = ["ft", "aet", "ft-pens", "ft-pen", "pens", "ap"]
    if finalStatuses.contains(s) || finalProgress.contains(p) || (p.hasPrefix("final") && !p.hasPrefix("final lap")) {
        return .final
    }
    let stoppedMarkers = ["delay", "postponed", "suspended", "canceled", "cancelled", "abandoned"]
    let stoppedCodes: Set<String> = ["pst", "susp", "canc", "abd", "int"]
    if stoppedCodes.contains(s) || stoppedCodes.contains(p) || stoppedMarkers.contains(where: { s.contains($0) || p.contains($0) }) {
        return .stopped
    }
    // Exactly halftime — never "1st Half" / "2nd Half", which are live play.
    if ["halftime", "half time", "half-time", "ht", "half"].contains(p) || s == "ht" {
        return .halftime
    }
    // "1st Intermission", "End of 2nd", MLB "Mid 5th" / "End 5th".
    if p.contains("intermission") || p.hasPrefix("mid ") || p.hasPrefix("end ") || p.hasPrefix("end of") {
        return .intermission
    }
    return .live
}

/// Renders the progress label appropriate for the activity variant —
/// live = pulsing red dot + period, halftime = orange HALF pill,
/// intermission / stopped = the status text without the dot, final = neutral FINAL pill.
@ViewBuilder
private func progressLabel(for state: LiveSportActivityAttributes.ContentState) -> some View {
    let variant = variantFor(progress: state.progress, status: state.status)
    switch variant {
    case .live:
        if let formatted = state.progress {
            HStack(spacing: 4) {
                Circle().fill(WidgetTokens.live).frame(width: 5, height: 5)
                Text(formatted)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(WidgetTokens.live)
            }
        }
    case .halftime:
        Text("HALF")
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .tracking(2)
            .foregroundStyle(WidgetTokens.star)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(WidgetTokens.star.opacity(0.18), in: Capsule())
    case .intermission, .stopped:
        // Static, no pulse: the clock isn't running.
        if let formatted = state.progress {
            Text(formatted)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(variant == .stopped ? WidgetTokens.star : WidgetTokens.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    case .final:
        Text(finalLabel(state.progress))
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .tracking(2)
            .foregroundStyle(WidgetTokens.inkSoft)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(WidgetTokens.alt, in: Capsule())
    }
}


/// "FINAL", or "FINAL/OT" / "FINAL/2OT" / "FINAL/SO" when the game went past regulation.
private func finalLabel(_ progress: String?) -> String {
    let p = (progress ?? "").uppercased()
    for extra in ["SO", "2OT", "3OT", "OT", "AET", "PENS"] where p.contains(extra) {
        return "FINAL/\(extra)"
    }
    return "FINAL"
}

/// Baseball's inning for the compact Dynamic Island: "▲9" top, "▼9" bottom,
/// "M9" / "E9" between halves. Nil for anything that isn't ESPN's "Top 9th" shape.
func compactInning(_ progress: String?) -> String? {
    let words = (progress ?? "").split(separator: " ")
    guard words.count == 2, let first = words.first, let last = words.last else { return nil }
    let digits = last.prefix { $0.isNumber }
    guard !digits.isEmpty, digits.count + 2 == last.count else { return nil }
    switch first.lowercased() {
    case "top": return "▲\(digits)"
    case "bot", "bottom": return "▼\(digits)"
    case "mid", "middle": return "M\(digits)"
    case "end": return "E\(digits)"
    default: return nil
    }
}

// MARK: - F1

/// Hex team colour → Color (the widget target doesn't link the app's Color helpers).
private func raceTeamColor(_ hex: String?) -> Color {
    guard let hex, hex.count == 6, let value = UInt64(hex, radix: 16) else { return WidgetTokens.inkSoft }
    return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
}

/// "Lap 23/62" → "L23"; anything else passes through trimmed for the compact slot.
private func compactLap(_ progress: String?, session: String) -> String {
    guard let progress, !progress.isEmpty else { return session }
    let digits = progress.split(whereSeparator: { !$0.isNumber })
    if progress.lowercased().contains("lap"), let lap = digits.first { return "L\(lap)" }
    return String(progress.prefix(6))
}

private struct RaceLeaderRow: View {
    let driver: LiveActivityRace.Driver
    let ink: Color
    var isGolf = false

    var body: some View {
        HStack(spacing: 6) {
            Text(driver.label ?? "\(driver.position)")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(ink.opacity(0.7))
                .frame(minWidth: isGolf ? 26 : 14, alignment: .trailing)
            if !isGolf {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(raceTeamColor(driver.teamColor))
                    .frame(width: 3, height: 14)
            }
            Text(driver.code)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let detail = driver.detail {
                Text(detail)
                    .font(.system(.caption2, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink.opacity(0.6))
            }
            Text(driver.gap ?? "Leader")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isGolf ? golfScoreColor(driver.gap, ink: ink) : ink.opacity(driver.gap == nil ? 1 : 0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if isGolf {
            let place = driver.label.map { $0.hasPrefix("T") ? "tied \($0.dropFirst())" : $0 } ?? "\(driver.position)"
            return "\(place), \(driver.code), \(driver.gap ?? "")\(driver.detail.map { ", \($0)" } ?? "")"
        }
        return "Position \(driver.position), \(driver.code)\(driver.gap.map { ", \($0) behind" } ?? ", leading")"
    }
}

/// Under par reads green, over par muted — the app's convention (`GolfScoreStyle`).
private func golfScoreColor(_ score: String?, ink: Color) -> Color {
    guard let score else { return ink }
    if score.hasPrefix("-") { return .green }
    return score.hasPrefix("+") ? ink.opacity(0.7) : ink
}

// MARK: - Tennis

private struct TennisSideRow: View {
    let name: String
    let side: GameSituation.Side
    let tennis: LiveActivityTennis
    let sets: Int
    let ink: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tennis.server == side ? WidgetTokens.live : Color.clear)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(.subheadline, design: .rounded).weight(tennis.winner == side ? .heavy : .semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            ForEach(Array(tennis.sets.enumerated()), id: \.offset) { _, set in
                Text(set.text(for: side))
                    .font(.system(.subheadline, design: .rounded).weight(set.winner == side ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(set.winner == nil || set.winner == side ? ink : ink.opacity(0.55))
                    .frame(minWidth: 18)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)\(tennis.server == side ? ", serving" : ""), \(sets) \(sets == 1 ? "set" : "sets")")
    }
}

private struct TennisLockScreenView: View {
    let attributes: LiveSportActivityAttributes
    let state: LiveSportActivityAttributes.ContentState
    let tennis: LiveActivityTennis

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "tennisball.fill")
                    .foregroundStyle(WidgetTokens.ink)
                Spacer()
                if let marker = tennis.marker {
                    Text(marker)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(WidgetTokens.inkSoft)
                }
                progressLabel(for: state)
            }
            TennisSideRow(name: attributes.homeTeam, side: .home, tennis: tennis, sets: state.homeScore, ink: WidgetTokens.ink)
            TennisSideRow(name: attributes.awayTeam, side: .away, tennis: tennis, sets: state.awayScore, ink: WidgetTokens.ink)
        }
    }
}

/// "6-4 3-2" style compact score: the set in play (or the last one).
private func tennisCompactScore(_ tennis: LiveActivityTennis) -> String {
    guard let current = tennis.sets.last else { return "0-0" }
    return "\(current.home)-\(current.away)"
}

private struct RaceLockScreenView: View {
    let raceName: String
    let state: LiveSportActivityAttributes.ContentState
    let race: LiveActivityRace

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: race.isGolf ? "figure.golf" : "flag.checkered")
                    .foregroundStyle(WidgetTokens.ink)
                Text(raceName)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(WidgetTokens.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                // Golf's progress already names the round ("Round 3 - In Progress"):
                // show it once, without the suffix, instead of "Round 3 • Round 3 – In Progre…".
                if (state.progress ?? "").hasPrefix(race.session) {
                    progressLabel(for: trimmedProgress(state))
                } else {
                    Text(race.session)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(WidgetTokens.inkSoft)
                    progressLabel(for: state)
                }
            }
            if race.leaders.isEmpty {
                Text("Waiting for timing…")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(WidgetTokens.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(race.leaders.enumerated()), id: \.offset) { _, driver in
                RaceLeaderRow(driver: driver, ink: WidgetTokens.ink, isGolf: race.isGolf)
            }
            if let following = race.following {
                Divider().overlay(WidgetTokens.inkSoft.opacity(0.4))
                RaceLeaderRow(driver: following, ink: WidgetTokens.ink, isGolf: true)
            }
        }
    }
}

// MARK: - Team sports

/// One side of a team-sport activity, with everything drawn beside it.
private struct ActivitySide {
    let side: GameSituation.Side
    let name: String
    let short: String
    let score: Int
    let opponentScore: Int
    let redCards: Int
    /// Football timeouts left; nil when the feed doesn't say (and for other sports).
    let timeouts: Int?
    /// The team's colour as 6-digit hex; nil when the activity predates it.
    let colorHex: String?

    var isWinning: Bool { score > opponentScore }

    /// "Arsenal 2, 1 red card", for VoiceOver.
    var spoken: String {
        var parts = ["\(name) \(score)"]
        if redCards > 0 { parts.append(redCards == 1 ? "1 red card" : "\(redCards) red cards") }
        if let timeouts { parts.append("\(timeouts) timeout\(timeouts == 1 ? "" : "s") left") }
        return parts.joined(separator: ", ")
    }
}

/// The two sides in display order: home first for soccer (`Game.displaysHomeFirst`,
/// carried on the attributes), away first elsewhere. Scores, red cards, timeouts and
/// the last scorer all hang off these, so they flip together.
private func activitySides(
    _ attributes: LiveSportActivityAttributes,
    _ state: LiveSportActivityAttributes.ContentState
) -> (first: ActivitySide, second: ActivitySide) {
    let home = ActivitySide(
        side: .home, name: attributes.homeTeam,
        short: shortAbbreviation(short: attributes.homeTeamShort, full: attributes.homeTeam),
        score: state.homeScore, opponentScore: state.awayScore,
        redCards: state.soccer?.homeRedCards ?? 0, timeouts: state.situation?.homeTimeouts,
        colorHex: attributes.homeColorHex
    )
    let away = ActivitySide(
        side: .away, name: attributes.awayTeam,
        short: shortAbbreviation(short: attributes.awayTeamShort, full: attributes.awayTeam),
        score: state.awayScore, opponentScore: state.homeScore,
        redCards: state.soccer?.awayRedCards ?? 0, timeouts: state.situation?.awayTimeouts,
        colorHex: attributes.awayColorHex
    )
    return attributes.displaysHomeFirst == true ? (home, away) : (away, home)
}

/// The state with " - In Progress" dropped from its progress ("Round 3 - In Progress").
private func trimmedProgress(_ state: LiveSportActivityAttributes.ContentState) -> LiveSportActivityAttributes.ContentState {
    var copy = state
    copy.progress = state.progress?.replacingOccurrences(of: " - In Progress", with: "")
    return copy
}

/// The two sides with the leader first; display order when level.
private func leaderFirst(_ sides: (first: ActivitySide, second: ActivitySide)) -> (first: ActivitySide, second: ActivitySide) {
    sides.second.isWinning ? (sides.second, sides.first) : sides
}

/// Where a line about one side sits: under the first side on the left, the second on
/// the right, centred when the side isn't known.
private func alignment(for side: GameSituation.Side?, first: GameSituation.Side) -> Alignment {
    guard let side else { return .center }
    return side == first ? .leading : .trailing
}

/// Football timeouts left, as three pips (the game detail's style).
private struct TimeoutPips: View {
    let name: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index < count ? tint : tint.opacity(0.25))
                    .frame(width: 8, height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(count) timeout\(count == 1 ? "" : "s") left")
    }
}

/// The latest goal, under the side that scored it.
private struct LastGoalLine: View {
    let goal: String
    let alignment: Alignment
    let tint: Color

    var body: some View {
        Label(goal, systemImage: "soccerball")
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: alignment)
            .accessibilityLabel("Last goal, \(goal)")
    }
}

/// Equal-width columns. Its ideal width is the widest column times the count, so a
/// `ViewThatFits` around it asks "does every column fit in its share?", not "does the
/// row's total fit?" (a plain HStack let "Los Angeles Lakers" pass, then truncate).
private struct EqualColumns: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let count = CGFloat(subviews.count)
        let gaps = spacing * (count - 1)
        let column = proposal.width.map { max(0, ($0 - gaps) / count) }
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: column * count + gaps, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = CGFloat(subviews.count)
        let column = max(0, (bounds.width - spacing * (count - 1)) / count)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (column + spacing), y: bounds.midY),
                          anchor: .leading, proposal: ProposedViewSize(width: column, height: bounds.height))
        }
    }
}

// MARK: - Team colours

/// A team's hex colour ("1D428A" or "#1D428A"), nudged so it reads on the activity:
/// near-black lifts toward white on a dark surface, near-white darkens on a light
/// one. Nil when unknown or malformed.
private func activityTeamColor(_ hex: String?, on scheme: ColorScheme) -> Color? {
    guard var hex = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
    let red = Double((value >> 16) & 0xFF) / 255
    let green = Double((value >> 8) & 0xFF) / 255
    let blue = Double(value & 0xFF) / 255
    let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
    let color = Color(red: red, green: green, blue: blue)
    if scheme == .dark, luminance < 0.2 { return color.mix(with: .white, by: 0.4) }
    if scheme == .light, luminance > 0.8 { return color.mix(with: .black, by: 0.4) }
    return color
}

/// The side that leads, nil when level.
private func leader(_ sides: (first: ActivitySide, second: ActivitySide)) -> ActivitySide? {
    sides.first.isWinning ? sides.first : (sides.second.isWinning ? sides.second : nil)
}

/// The Lock Screen card's wash: the first side's colour fading into the second's.
/// Nothing when either colour is unknown, so the card stays as it was.
private struct TeamColorWash: View {
    let first: ActivitySide
    let second: ActivitySide
    /// Top to bottom, for the small card's stacked rows.
    var vertical = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let left = activityTeamColor(first.colorHex, on: scheme),
           let right = activityTeamColor(second.colorHex, on: scheme) {
            let strength = scheme == .dark ? 0.34 : 0.2
            LinearGradient(colors: [left.opacity(strength), left.opacity(strength * 0.35),
                                    right.opacity(strength * 0.35), right.opacity(strength)],
                           startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing)
        }
    }
}

/// Win probability as a two-colour bar, "BUF 42%" on the left and "58% KC" on the
/// right, in display order.
private struct ActivityWinBar: View {
    let first: ActivitySide
    let second: ActivitySide
    /// The home side's chance, 0-100.
    let homePercent: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let firstPercent = first.side == .home ? homePercent : 100 - homePercent
        let firstColor = activityTeamColor(first.colorHex, on: scheme) ?? WidgetTokens.ink
        let secondColor = activityTeamColor(second.colorHex, on: scheme) ?? WidgetTokens.inkFaint
        HStack(spacing: 6) {
            Text("\(first.short) \(firstPercent)%")
            GeometryReader { proxy in
                let split = proxy.size.width * CGFloat(min(max(firstPercent, 0), 100)) / 100
                HStack(spacing: 2) {
                    Capsule().fill(firstColor).frame(width: max(split - 1, 2))
                    Capsule().fill(secondColor)
                }
            }
            .frame(height: 5)
            Text("\(100 - firstPercent)% \(second.short)")
        }
        .font(.system(.caption2, design: .rounded).weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(WidgetTokens.inkSoft)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Win probability, \(first.name) \(firstPercent) percent, \(second.name) \(100 - firstPercent) percent")
    }
}

/// "WIN" in the winner's colour, under its side on a final.
private struct WinnerPill: View {
    let side: ActivitySide
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text("WIN")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(activityTeamColor(side.colorHex, on: scheme) ?? WidgetTokens.ink))
            .accessibilityLabel("\(side.name) won")
    }
}

private struct TeamLockScreenView: View {
    let attributes: LiveSportActivityAttributes
    let state: LiveSportActivityAttributes.ContentState

    private var isFinal: Bool { variantFor(progress: state.progress, status: state.status) == .final }

    var body: some View {
        let sides = activitySides(attributes, state)
        VStack(spacing: 8) {
            // Both sides share one name style: full names at the largest size where
            // both fit, else both codes. Deciding per side showed "LAL" beside
            // "Boston Celtics".
            ViewThatFits(in: .horizontal) {
                scoreRow(sides, nameFont: .headline)
                scoreRow(sides, nameFont: .subheadline)
                scoreRow(sides, nameFont: .footnote)
                scoreRow(sides, nameFont: nil)
            }
            if isFinal, let winner = leader(sides) {
                HStack {
                    if winner.side == sides.first.side { WinnerPill(side: winner) }
                    Spacer(minLength: 8)
                    if winner.side == sides.second.side { WinnerPill(side: winner) }
                }
            }
            if sides.first.timeouts != nil || sides.second.timeouts != nil {
                HStack {
                    timeouts(sides.first)
                    Spacer(minLength: 8)
                    timeouts(sides.second)
                }
            }
            if let situation = state.situation {
                LiveActivitySituationStrip(
                    situation: situation,
                    homeName: shortAbbreviation(short: attributes.homeTeamShort, full: attributes.homeTeam),
                    awayName: shortAbbreviation(short: attributes.awayTeamShort, full: attributes.awayTeam),
                    tint: WidgetTokens.inkSoft,
                    showsWinProbability: false
                )
                .frame(maxWidth: .infinity, alignment: .center)
                if let percent = situation.homeWinPct, !isFinal {
                    ActivityWinBar(first: sides.first, second: sides.second, homePercent: percent)
                }
            }
            if let soccer = state.soccer, let lastGoal = soccer.lastGoal {
                LastGoalLine(goal: lastGoal, alignment: alignment(for: soccer.lastGoalSide, first: sides.first.side),
                             tint: WidgetTokens.inkSoft)
            }
            if let lastPlay = state.lastPlay, !lastPlay.isEmpty {
                Text(lastPlay)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(WidgetTokens.inkSoft)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        // Scores roll to the new number when an update lands.
        .contentTransition(.numericText())
        .animation(.spring(duration: 0.4), value: state.homeScore)
        .animation(.spring(duration: 0.4), value: state.awayScore)
    }

    private func scoreRow(_ sides: (first: ActivitySide, second: ActivitySide), nameFont: Font?) -> some View {
        EqualColumns {
            team(sides.first, leading: true, nameFont: nameFont)
            progressLabel(for: state)
                .frame(maxWidth: .infinity, alignment: .center)
            team(sides.second, leading: false, nameFont: nameFont)
        }
    }

    /// `IndividualTeamView`'s `isAway` lays a side out leading (badge, then score).
    /// A `nameFont` shows the full name at that size; nil shows the team code.
    private func team(_ side: ActivitySide, leading: Bool, nameFont: Font?) -> some View {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?
            .appendingPathComponent(side.name)
        let data = url.flatMap { try? Data(contentsOf: $0) }
        // On a final the loser fades back.
        let faded = isFinal && side.score < side.opponentScore
        return Group {
            if let nameFont {
                IndividualTeamView(longName: side.name, score: side.score, isWinning: side.isWinning,
                                   isAway: leading, redCards: side.redCards, data: data,
                                   fallbackName: side.short, nameFont: nameFont)
            } else {
                IndividualTeamView(shortName: side.short, longName: side.name, score: side.score, isWinning: side.isWinning,
                                   isAway: leading, redCards: side.redCards, data: data, fallbackName: side.short)
            }
        }
        .opacity(faded ? 0.5 : 1)
    }

    @ViewBuilder
    private func timeouts(_ side: ActivitySide) -> some View {
        if let count = side.timeouts {
            TimeoutPips(name: side.short, count: count, tint: WidgetTokens.inkSoft)
        }
    }
}

/// "2-1" with the leading side's score heavy and the trailing one dimmed, so the
/// lead reads at a glance in the compact and minimal slots. A tie draws both evenly.
private struct LeadScoreText: View {
    let first: Int
    let second: Int
    let size: CGFloat

    var body: some View {
        // One Text, so "112-108" scales down as a whole instead of each number
        // truncating to "1…" in the minimal bubble.
        (score(first, leads: first > second, trails: first < second)
         + Text("-").foregroundStyle(WidgetTokens.inkSoft)
         + score(second, leads: second > first, trails: second < first))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .contentTransition(.numericText())
    }

    private func score(_ value: Int, leads: Bool, trails: Bool) -> Text {
        Text("\(value)")
            .fontWeight(leads ? .heavy : .semibold)
            .foregroundStyle(trails ? WidgetTokens.inkSoft : WidgetTokens.ink)
    }
}

/// The minimal Dynamic Island slot: the small bubble beside the camera when another
/// activity holds the island, and the iPhone Duo's outer camera cut-out. Both scores,
/// with the leader's code above them; "TIE" when level.
private struct MinimalScoreView: View {
    let first: ActivitySide
    let second: ActivitySide

    var body: some View {
        let leader = first.isWinning ? first : (second.isWinning ? second : nil)
        VStack(spacing: 0) {
            Text(leader?.short ?? "TIE")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(leader == nil ? WidgetTokens.inkSoft : WidgetTokens.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            LeadScoreText(first: first.score, second: second.score, size: 11)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(leader.map { "\($0.name) leads, \(first.spoken), \(second.spoken)" }
                            ?? "Tied, \(first.spoken), \(second.spoken)")
    }
}

/// One side in the expanded Dynamic Island: badge on the outside, then the score,
/// the name and (football) the timeouts left.
private struct ExpandedIslandSide: View {
    let side: ActivitySide
    let leading: Bool
    /// The island is always dark.
    private var teamColor: Color? { activityTeamColor(side.colorHex, on: .dark) }

    var body: some View {
        HStack {
            if leading { badgeImage(for: side.name, code: side.short, size: 35) }
            VStack(spacing: 2) {
                Text("\(side.score)")
                    .font(.system(size: 24))
                    .fontWeight(side.isWinning ? .heavy : .regular)
                    .foregroundStyle(side.isWinning ? Color.primary : Color.secondary)
                    .contentTransition(.numericText(value: Double(side.score)))
                HStack(spacing: 3) {
                    if !leading, side.redCards > 0 { SoccerRedCardMark(count: side.redCards) }
                    // A code, on one line: full names ("Kansas City Chiefs") wrapped and
                    // pushed the island taller, and still truncated when scaled.
                    Text(side.short)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(teamColor ?? Color.primary)
                        .lineLimit(1)
                    if leading, side.redCards > 0 { SoccerRedCardMark(count: side.redCards) }
                }
                if let timeouts = side.timeouts {
                    TimeoutPips(name: side.short, count: timeouts, tint: WidgetTokens.ink)
                }
            }
            if !leading { badgeImage(for: side.name, code: side.short, size: 35) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(side.spoken)
    }
}

// MARK: - Content: Lock Screen / StandBy (medium) and CarPlay / Watch (small)

/// Picks the layout for the presentation: the full card on the Lock Screen,
/// banners and StandBy; the compact `.small` card on CarPlay and the Watch.
private struct ActivityContentView: View {
    let attributes: LiveSportActivityAttributes
    let state: LiveSportActivityAttributes.ContentState
    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            SmallActivityView(attributes: attributes, state: state)
        } else if let race = state.race {
            RaceLockScreenView(raceName: attributes.homeTeam, state: state, race: race)
                .padding(16)
        } else if let tennis = state.tennis {
            TennisLockScreenView(attributes: attributes, state: state, tennis: tennis)
                .padding(16)
        } else {
            let sides = activitySides(attributes, state)
            TeamLockScreenView(attributes: attributes, state: state)
                .padding(16)
                .background { TeamColorWash(first: sides.first, second: sides.second) }
        }
    }
}

/// CarPlay and the Watch Smart Stack: glanceable at arm's length. Team sports get
/// two rows (colour bar, logo, code, score) over the clock; races their top two
/// (plus your golfer); tennis both players' sets.
private struct SmallActivityView: View {
    let attributes: LiveSportActivityAttributes
    let state: LiveSportActivityAttributes.ContentState

    var body: some View {
        Group {
            if let race = state.race {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: race.isGolf ? "figure.golf" : "flag.checkered")
                        Text(attributes.homeTeam).lineLimit(1)
                        Spacer(minLength: 4)
                        progressLabel(for: trimmedProgress(state))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(WidgetTokens.ink)
                    ForEach(Array(race.leaders.prefix(race.following == nil ? 3 : 2).enumerated()), id: \.offset) { _, driver in
                        RaceLeaderRow(driver: driver, ink: WidgetTokens.ink, isGolf: race.isGolf)
                    }
                    if let following = race.following {
                        RaceLeaderRow(driver: following, ink: WidgetTokens.ink, isGolf: true)
                    }
                }
            } else if let tennis = state.tennis {
                VStack(spacing: 4) {
                    TennisSideRow(name: attributes.homeTeam, side: .home, tennis: tennis, sets: state.homeScore, ink: WidgetTokens.ink)
                    TennisSideRow(name: attributes.awayTeam, side: .away, tennis: tennis, sets: state.awayScore, ink: WidgetTokens.ink)
                    progressLabel(for: state)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                let sides = activitySides(attributes, state)
                let isFinal = variantFor(progress: state.progress, status: state.status) == .final
                VStack(spacing: 4) {
                    SmallTeamRow(side: sides.first, isFinal: isFinal)
                    SmallTeamRow(side: sides.second, isFinal: isFinal)
                    HStack(spacing: 6) {
                        progressLabel(for: state)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 4)
                        if let percent = state.situation?.homeWinPct, !isFinal {
                            let leader = percent >= 50 ? (sides.first.side == .home ? sides.first : sides.second)
                                                       : (sides.first.side == .away ? sides.first : sides.second)
                            Text("\(leader.short) \(max(percent, 100 - percent))%")
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(WidgetTokens.inkSoft)
                        }
                    }
                }
                .background { TeamColorWash(first: sides.first, second: sides.second, vertical: true).padding(-12) }
            }
        }
        .padding(12)
        .contentTransition(.numericText())
    }
}

/// One side on the small card: colour bar, logo, code, then the score on the right.
private struct SmallTeamRow: View {
    let side: ActivitySide
    let isFinal: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let faded = isFinal && side.score < side.opponentScore
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(activityTeamColor(side.colorHex, on: scheme) ?? WidgetTokens.inkFaint)
                .frame(width: 3, height: 20)
            badgeImage(for: side.name, code: side.short, size: 22)
            Text(side.short)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .lineLimit(1)
            if side.redCards > 0 { SoccerRedCardMark(count: side.redCards) }
            Spacer(minLength: 4)
            if isFinal, side.isWinning {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(activityTeamColor(side.colorHex, on: scheme) ?? WidgetTokens.ink)
            }
            Text("\(side.score)")
                .font(.system(.title3, design: .rounded).weight(side.isWinning ? .heavy : .semibold))
                .monospacedDigit()
                .foregroundStyle(side.isWinning || side.score == side.opponentScore ? WidgetTokens.ink : WidgetTokens.inkSoft)
        }
        .foregroundStyle(WidgetTokens.ink)
        .opacity(faded ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(side.spoken)
    }
}

struct LiveSportActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveSportActivityAttributes.self) { context in
            ActivityContentView(attributes: context.attributes, state: context.state)
                // System chrome (the lock-screen dismiss/action control) follows the
                // Themes accent.
                .activitySystemActionForegroundColor(WidgetTokens.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let race = context.state.race {
                        Label(race.session, systemImage: race.isGolf ? "figure.golf" : "flag.checkered")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(WidgetTokens.ink)
                    } else if context.state.tennis != nil {
                        Image(systemName: "tennisball.fill")
                            .foregroundStyle(WidgetTokens.ink)
                            .padding(.leading, 6)
                    } else {
                        ExpandedIslandSide(side: activitySides(context.attributes, context.state).first, leading: true)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.race != nil || context.state.tennis != nil {
                        progressLabel(for: context.state)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.trailing, 6)
                    } else {
                        ExpandedIslandSide(side: activitySides(context.attributes, context.state).second, leading: false)
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    // "LIVE" only while play is running: not over a FINAL or HALF pill.
                    if context.state.race == nil && context.state.tennis == nil,
                       variantFor(progress: context.state.progress, status: context.state.status) == .live {
                        LiveAnimatedView()
                            .transition(.scale(scale: 2.5))
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    if let race = context.state.race {
                        VStack(spacing: 4) {
                            ForEach(Array(race.leaders.enumerated()), id: \.offset) { _, driver in
                                RaceLeaderRow(driver: driver, ink: WidgetTokens.ink, isGolf: race.isGolf)
                            }
                            if let following = race.following {
                                RaceLeaderRow(driver: following, ink: WidgetTokens.ink, isGolf: true)
                            }
                        }
                    } else if let tennis = context.state.tennis {
                        VStack(spacing: 4) {
                            TennisSideRow(name: context.attributes.homeTeam, side: .home, tennis: tennis, sets: context.state.homeScore, ink: WidgetTokens.ink)
                            TennisSideRow(name: context.attributes.awayTeam, side: .away, tennis: tennis, sets: context.state.awayScore, ink: WidgetTokens.ink)
                        }
                    } else {
                    VStack(spacing: 2) {
                        progressLabel(for: context.state)
                            .frame(maxWidth: .infinity, alignment: .center)
                        if let situation = context.state.situation {
                            LiveActivitySituationStrip(
                                situation: situation,
                                homeName: shortAbbreviation(short: context.attributes.homeTeamShort, full: context.attributes.homeTeam),
                                awayName: shortAbbreviation(short: context.attributes.awayTeamShort, full: context.attributes.awayTeam),
                                tint: WidgetTokens.ink
                            )
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        if let soccer = context.state.soccer, let lastGoal = soccer.lastGoal {
                            LastGoalLine(goal: lastGoal,
                                         alignment: alignment(for: soccer.lastGoalSide, first: activitySides(context.attributes, context.state).first.side),
                                         tint: WidgetTokens.ink)
                        }
                        if let lastPlay = context.state.lastPlay, !lastPlay.isEmpty {
                            Text(lastPlay)
                                .font(.system(.caption2, design: .rounded).weight(.medium))
                                .foregroundStyle(WidgetTokens.ink)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    }
                }
                
            } compactLeading: {
                // Apple's Dynamic Island compact slot tints raster images into
                // silhouettes (Apple HIG: "use SF Symbols, avoid complex images").
                // Use the team's short abbreviation instead — always legible,
                // never tinted, identifies the team at a glance. Real logos still
                // show in expanded and on the lock screen.
                if let race = context.state.race {
                    HStack(spacing: 3) {
                        Image(systemName: race.isGolf ? "figure.golf" : "flag.checkered")
                        Text((race.following ?? race.leaders.first)?.code ?? race.session)
                            .lineLimit(1)
                    }
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundColor(WidgetTokens.ink)
                } else if context.state.tennis != nil {
                    HStack(spacing: 3) {
                        Image(systemName: "tennisball.fill")
                        Text("\(context.state.homeScore)-\(context.state.awayScore)")
                            .monospacedDigit()
                    }
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundColor(WidgetTokens.ink)
                } else {
                    // The leader's code, with its score first on the trailing side:
                    // "KC 20-17" reads as who's winning at a glance.
                    let sides = activitySides(context.attributes, context.state)
                    let lead = leaderFirst(sides)
                    HStack(spacing: 3) {
                        // The leader's colour; no dot when level.
                        if leader(sides) != nil, let color = activityTeamColor(lead.first.colorHex, on: .dark) {
                            Circle().fill(color).frame(width: 6, height: 6)
                        }
                        Text(lead.first.short)
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .foregroundColor(WidgetTokens.ink)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(lead.first.name)
                }
            } compactTrailing: {
                if let race = context.state.race {
                    Text(race.isGolf ? ((race.following ?? race.leaders.first)?.gap ?? race.session)
                         : compactLap(context.state.progress, session: race.session))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundColor(WidgetTokens.ink)
                } else if let tennis = context.state.tennis {
                    Text(tennisCompactScore(tennis))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundColor(WidgetTokens.ink)
                } else {
                let sides = leaderFirst(activitySides(context.attributes, context.state))
                HStack(spacing: 3) {
                    LeadScoreText(first: sides.first.score, second: sides.second.score, size: 12)
                        // "2-1" reads as "2 minus 1".
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(sides.first.short) \(sides.first.score), \(sides.second.short) \(sides.second.score)")
                    if let inning = compactInning(context.state.progress) {
                        Text(inning)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundColor(WidgetTokens.inkSoft)
                            .accessibilityLabel(context.state.progress ?? inning)
                    }
                }
                }
            } minimal: {
                if context.state.tennis != nil {
                    VStack(spacing: 0) {
                        Image(systemName: "tennisball.fill")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundColor(WidgetTokens.ink)
                        LeadScoreText(first: context.state.homeScore, second: context.state.awayScore, size: 11)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Sets \(context.attributes.homeTeam) \(context.state.homeScore), \(context.attributes.awayTeam) \(context.state.awayScore)")
                } else if let race = context.state.race {
                    // Golf: your player's place ("T24"), else the leader's score.
                    // Racing: the leader's code ("PIA").
                    let focus = race.following ?? race.leaders.first
                    VStack(spacing: 0) {
                        Image(systemName: race.isGolf ? "figure.golf" : "flag.checkered")
                            .font(.system(size: 7, weight: .heavy))
                        Text((race.isGolf ? (race.following?.label ?? focus?.gap) : focus?.code) ?? race.session)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .foregroundColor(WidgetTokens.ink)
                } else {
                    // Leader first, like compact: "KC" over "20-17".
                    let sides = leaderFirst(activitySides(context.attributes, context.state))
                    MinimalScoreView(first: sides.first, second: sides.second)
                }
            }
            // The leading team's colour on the island's outline; the Themes accent
            // when level or for races, tennis and activities without colours.
            .keylineTint(keyline(context))
        }
        // The small family: CarPlay (iOS 26) and the Apple Watch Smart Stack. Without
        // it both fell back to the island's compact views.
        .supplementalActivityFamilies([.small, .medium])
    }

    private func keyline(_ context: ActivityViewContext<LiveSportActivityAttributes>) -> Color {
        guard context.state.race == nil, context.state.tennis == nil,
              let lead = leader(activitySides(context.attributes, context.state)),
              let color = activityTeamColor(lead.colorHex, on: .dark) else { return WidgetTokens.accent }
        return color
    }
}

#Preview("Island Compact", as: .dynamicIsland(.compact), using: LiveSportActivityAttributes(homeTeam: "VGK", awayTeam: "EDM", eventID: "401459774")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 3, awayScore: 6, status: "in", progress: "2:14 - 2nd", lastPlay: "Goal by McDavid (PP)")
}

#Preview("Island Expanded", as: .dynamicIsland(.expanded), using: LiveSportActivityAttributes(homeTeam: "VGK", awayTeam: "EDM", eventID: "401459774")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 3, awayScore: 6, status: "in", progress: "2:14 - 2nd", lastPlay: "Goal by McDavid (PP)")
}

#Preview("Notification", as: .content, using: LiveSportActivityAttributes(homeTeam: "VGK", awayTeam: "EDM", eventID: "401459774")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 3, awayScore: 6, status: "in", progress: "2:14 - 2nd", lastPlay: "Goal by McDavid (PP)")
}

#Preview("Notification · Baseball", as: .content, using: LiveSportActivityAttributes(homeTeam: "Cleveland Guardians", awayTeam: "Detroit Tigers", eventID: "1", homeTeamShort: "CLE", awayTeamShort: "DET")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 3, awayScore: 5, status: "in", progress: "Bot 9th", lastPlay: "Kwan singled to left.",
                                             situation: LiveActivitySituation(outs: 1, bases: 3, homeWinPct: 21))
}

#Preview("Island Expanded · Football", as: .dynamicIsland(.expanded), using: LiveSportActivityAttributes(homeTeam: "Kansas City Chiefs", awayTeam: "Buffalo Bills", eventID: "2", homeTeamShort: "KC", awayTeamShort: "BUF")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 20, awayScore: 17, status: "in", progress: "4th 2:31", lastPlay: nil,
                                             situation: LiveActivitySituation(downDistance: "3rd & 4 at KC 12", possession: .away, redZone: true, homeWinPct: 58,
                                                                              homeTimeouts: 2, awayTimeouts: 1))
}

#Preview("Notification · Football", as: .content, using: LiveSportActivityAttributes(homeTeam: "Kansas City Chiefs", awayTeam: "Buffalo Bills", eventID: "2", homeTeamShort: "KC", awayTeamShort: "BUF")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 20, awayScore: 17, status: "in", progress: "4th 2:31", lastPlay: nil,
                                             situation: LiveActivitySituation(downDistance: "3rd & 4 at KC 12", possession: .away, redZone: true, homeWinPct: 58,
                                                                              homeTimeouts: 2, awayTimeouts: 1))
}

private let previewSoccerAttributes = LiveSportActivityAttributes(homeTeam: "Arsenal", awayTeam: "Chelsea", eventID: "soccer",
                                                                  homeTeamShort: "ARS", awayTeamShort: "CHE", displaysHomeFirst: true,
                                                                  homeColorHex: "EF0107", awayColorHex: "034694")
private let previewSoccerState = LiveSportActivityAttributes.ContentState(
    homeScore: 2, awayScore: 1, status: "in", progress: "67'",
    soccer: LiveActivitySoccer(awayRedCards: 1, lastGoal: "Saka 64'", lastGoalSide: .home)
)

#Preview("Notification · Soccer", as: .content, using: previewSoccerAttributes) {
    LiveSportActivityWidget()
} contentStates: {
    previewSoccerState
}

#Preview("Island Expanded · Soccer", as: .dynamicIsland(.expanded), using: previewSoccerAttributes) {
    LiveSportActivityWidget()
} contentStates: {
    previewSoccerState
}

// Names too long for a third of the Lock Screen: they step down, then fall back to codes.
#Preview("Notification · Soccer long names", as: .content, using: LiveSportActivityAttributes(
    homeTeam: "Brighton & Hove Albion", awayTeam: "Wolverhampton Wanderers", eventID: "soccer-long",
    homeTeamShort: "BHA", awayTeamShort: "WOL", displaysHomeFirst: true)) {
    LiveSportActivityWidget()
} contentStates: {
    previewSoccerState
}
private let previewGolf = LiveActivityRace(session: "Round 3", leaders: [
    .init(position: 1, code: "S. Scheffler", gap: "-15", label: "1", detail: "Thru 14"),
    .init(position: 2, code: "R. McIlroy", gap: "-13", label: "T2", detail: "Thru 12"),
    .init(position: 3, code: "X. Schauffele", gap: "-13", label: "T2", detail: "F"),
], sport: "golf", following: .init(position: 24, code: "L. Åberg", gap: "-6", label: "T24", detail: "Thru 9"))

#Preview("Notification · Golf", as: .content, using: LiveSportActivityAttributes(homeTeam: "The Masters", awayTeam: "Ludvig Åberg", eventID: "golf", homeTeamShort: "GOLF")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 0, awayScore: 0, status: "in", progress: "Round 3 - In Progress", race: previewGolf)
}

#Preview("Notification · Tennis", as: .content, using: LiveSportActivityAttributes(homeTeam: "Jannik Sinner", awayTeam: "Carlos Alcaraz", eventID: "tennis")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 1, awayScore: 1, status: "in", progress: "3rd Set", tennis: LiveActivityTennis(sets: [
        .init(home: 7, away: 6, homeTiebreak: 7, awayTiebreak: 4, winner: .home),
        .init(home: 4, away: 6, winner: .away),
        .init(home: 3, away: 2),
    ], server: .home))
}

private let previewRace = LiveActivityRace(session: "Race", leaders: [
    .init(position: 1, code: "PIA", gap: nil, teamColor: "F47600"),
    .init(position: 2, code: "NOR", gap: "+1.204", teamColor: "F47600"),
    .init(position: 3, code: "RUS", gap: "+3.900", teamColor: "00D7B6"),
])

#Preview("Notification · F1", as: .content, using: LiveSportActivityAttributes(homeTeam: "Singapore Grand Prix", awayTeam: "Formula 1", eventID: "f1", homeTeamShort: "F1")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 0, awayScore: 0, status: "in", progress: "Lap 23/62", race: previewRace)
}

#Preview("Island Expanded · F1", as: .dynamicIsland(.expanded), using: LiveSportActivityAttributes(homeTeam: "Singapore Grand Prix", awayTeam: "Formula 1", eventID: "f1", homeTeamShort: "F1")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 0, awayScore: 0, status: "in", progress: "Lap 23/62", race: previewRace)
}

#Preview("Island Compact · F1", as: .dynamicIsland(.compact), using: LiveSportActivityAttributes(homeTeam: "Singapore Grand Prix", awayTeam: "Formula 1", eventID: "f1", homeTeamShort: "F1")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 0, awayScore: 0, status: "in", progress: "Lap 23/62", race: previewRace)
}

// MARK: - Gallery: every presentation for each scenario (docs/live-activities gallery)

private let galleryNBA = LiveSportActivityAttributes(homeTeam: "Boston Celtics", awayTeam: "Los Angeles Lakers", eventID: "g-nba",
                                                     homeTeamShort: "BOS", awayTeamShort: "LAL",
                                                     homeColorHex: "007A33", awayColorHex: "552583")
private let galleryNBAState = LiveSportActivityAttributes.ContentState(homeScore: 108, awayScore: 112, status: "in", progress: "4th 2:14",
                                                                       lastPlay: "LeBron James makes 26-foot three point jumper")
private let galleryNHL = LiveSportActivityAttributes(homeTeam: "Vegas Golden Knights", awayTeam: "Edmonton Oilers", eventID: "g-nhl",
                                                     homeTeamShort: "VGK", awayTeamShort: "EDM",
                                                     homeColorHex: "B4975A", awayColorHex: "041E42")
private let galleryNHLTied = LiveSportActivityAttributes.ContentState(homeScore: 2, awayScore: 2, status: "in", progress: "5:40 - 3rd",
                                                                      lastPlay: "Goal by Eichel (PP)")
private let galleryMLB = LiveSportActivityAttributes(homeTeam: "Cleveland Guardians", awayTeam: "Detroit Tigers", eventID: "g-mlb",
                                                     homeTeamShort: "CLE", awayTeamShort: "DET",
                                                     homeColorHex: "E31937", awayColorHex: "0C2340")
private let galleryMLBState = LiveSportActivityAttributes.ContentState(homeScore: 3, awayScore: 5, status: "in", progress: "Bot 9th",
                                                                       lastPlay: "Kwan singled to left.",
                                                                       situation: LiveActivitySituation(outs: 1, bases: 3, homeWinPct: 21))
private let galleryNFL = LiveSportActivityAttributes(homeTeam: "Kansas City Chiefs", awayTeam: "Buffalo Bills", eventID: "g-nfl",
                                                     homeTeamShort: "KC", awayTeamShort: "BUF",
                                                     homeColorHex: "E31837", awayColorHex: "00338D")
private let galleryNFLState = LiveSportActivityAttributes.ContentState(homeScore: 20, awayScore: 17, status: "in", progress: "4th 2:31", lastPlay: nil,
                                                                       situation: LiveActivitySituation(downDistance: "3rd & 4 at KC 12", possession: .away, redZone: true,
                                                                                                        homeWinPct: 58, homeTimeouts: 2, awayTimeouts: 1))
private let gallerySoccerHT = LiveSportActivityAttributes.ContentState(homeScore: 0, awayScore: 0, status: "in", progress: "HT")
private let galleryNBAFinal = LiveSportActivityAttributes.ContentState(homeScore: 121, awayScore: 117, status: "post", progress: "Final/OT")
private let galleryTennis = LiveSportActivityAttributes(homeTeam: "Jannik Sinner", awayTeam: "Carlos Alcaraz", eventID: "g-tennis")
private let galleryTennisState = LiveSportActivityAttributes.ContentState(homeScore: 1, awayScore: 1, status: "in", progress: "3rd Set",
                                                                          tennis: LiveActivityTennis(sets: [
                                                                            .init(home: 7, away: 6, homeTiebreak: 7, awayTiebreak: 4, winner: .home),
                                                                            .init(home: 4, away: 6, winner: .away),
                                                                            .init(home: 3, away: 2),
                                                                          ], server: .home))
private let galleryF1 = LiveSportActivityAttributes(homeTeam: "Singapore Grand Prix", awayTeam: "Formula 1", eventID: "g-f1", homeTeamShort: "F1")
private let galleryF1State = LiveSportActivityAttributes.ContentState(homeScore: 0, awayScore: 0, status: "in", progress: "Lap 23/62", race: previewRace)
private let galleryGolf = LiveSportActivityAttributes(homeTeam: "The Masters", awayTeam: "Ludvig Åberg", eventID: "g-golf", homeTeamShort: "GOLF")
private let galleryGolfState = LiveSportActivityAttributes.ContentState(homeScore: 0, awayScore: 0, status: "in", progress: "Round 3 - In Progress", race: previewGolf)

// One preview per scenario; switch Xcode's "View Style" variant (Lock Screen,
// StandBy, Smart Stack, compact, minimal, expanded) to see every presentation.
#Preview("Gallery · NBA", as: .content, using: galleryNBA) { LiveSportActivityWidget() } contentStates: { galleryNBAState }
#Preview("Gallery · NHL tied", as: .content, using: galleryNHL) { LiveSportActivityWidget() } contentStates: { galleryNHLTied }
#Preview("Gallery · MLB", as: .content, using: galleryMLB) { LiveSportActivityWidget() } contentStates: { galleryMLBState }
#Preview("Gallery · NFL", as: .content, using: galleryNFL) { LiveSportActivityWidget() } contentStates: { galleryNFLState }
#Preview("Gallery · Soccer", as: .content, using: previewSoccerAttributes) { LiveSportActivityWidget() } contentStates: { previewSoccerState }
#Preview("Gallery · Soccer HT", as: .content, using: previewSoccerAttributes) { LiveSportActivityWidget() } contentStates: { gallerySoccerHT }
#Preview("Gallery · NBA final", as: .content, using: galleryNBA) { LiveSportActivityWidget() } contentStates: { galleryNBAFinal }
#Preview("Gallery · Tennis", as: .content, using: galleryTennis) { LiveSportActivityWidget() } contentStates: { galleryTennisState }
#Preview("Gallery · F1", as: .content, using: galleryF1) { LiveSportActivityWidget() } contentStates: { galleryF1State }
#Preview("Gallery · Golf", as: .content, using: galleryGolf) { LiveSportActivityWidget() } contentStates: { galleryGolfState }
#Preview("Gallery · NFL final", as: .content, using: galleryNFL) { LiveSportActivityWidget() } contentStates: { LiveSportActivityAttributes.ContentState(homeScore: 27, awayScore: 24, status: "post", progress: "Final/OT") }
#endif
#endif
