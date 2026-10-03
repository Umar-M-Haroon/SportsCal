//
//  LiveSportActivityWidget.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/28/22.
//

import SwiftUI
import WidgetKit
import UIKit
import SportsCalModel
#if canImport(ActivityKit)

/// Loads a team badge image from the shared app group container, with a fallback to team initials.
/// Used by the lock screen and expanded Dynamic Island where raster images render in full color.
@ViewBuilder
private func badgeImage(for teamName: String, size: CGFloat) -> some View {
    if let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(teamName),
       let data = try? Data(contentsOf: fileURL),
       let image = UIImage(data: data) {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    } else {
        teamInitialsView(teamName, size: size)
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
private func teamInitialsView(_ teamName: String, size: CGFloat) -> some View {
    ZStack {
        Circle()
            .fill(.white.opacity(0.18))
            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
            .frame(width: size, height: size)
        Text(Team.shortCode(strTeamShort: nil, name: teamName))
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
}

private func variantFor(progress: String?, status: String?) -> LiveActivityVariant {
    let p = (progress ?? "").lowercased()
    let s = (status ?? "").lowercased()
    if s == "ft" || s == "aet" || s == "final" || p.contains("final") {
        return .final
    }
    if p.contains("half") && !p.contains("first") && !p.contains("second") {
        // "Halftime", "HT", "Half" — but not "First Half" / "Second Half"
        return .halftime
    }
    if p == "ht" || p == "halftime" {
        return .halftime
    }
    return .live
}

/// Renders the progress label appropriate for the activity variant —
/// live = pulsing red dot + period, halftime = orange HALF pill,
/// final = neutral FINAL pill.
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
    case .final:
        Text("FINAL")
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .tracking(2)
            .foregroundStyle(WidgetTokens.inkSoft)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(WidgetTokens.alt, in: Capsule())
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

    var body: some View {
        HStack(spacing: 6) {
            Text("\(driver.position)")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(ink.opacity(0.7))
                .frame(width: 14, alignment: .trailing)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(raceTeamColor(driver.teamColor))
                .frame(width: 3, height: 14)
            Text(driver.code)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(ink)
            Spacer(minLength: 4)
            Text(driver.gap ?? "Leader")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ink.opacity(driver.gap == nil ? 1 : 0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position \(driver.position), \(driver.code)\(driver.gap.map { ", \($0) behind" } ?? ", leading")")
    }
}

private struct RaceLockScreenView: View {
    let raceName: String
    let state: LiveSportActivityAttributes.ContentState
    let race: LiveActivityRace

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(WidgetTokens.ink)
                Text(raceName)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(WidgetTokens.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(race.session)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(WidgetTokens.inkSoft)
                progressLabel(for: state)
            }
            if race.leaders.isEmpty {
                Text("Waiting for timing…")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(WidgetTokens.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(race.leaders, id: \.position) { driver in
                RaceLeaderRow(driver: driver, ink: WidgetTokens.ink)
            }
        }
    }
}

struct LiveSportActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveSportActivityAttributes.self) { context in
            if let race = context.state.race {
                RaceLockScreenView(raceName: context.attributes.homeTeam, state: context.state, race: race)
                    .padding(16)
            } else {
            VStack(spacing: 8) {
                HStack {
                    if let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(context.attributes.awayTeam) {
                        IndividualTeamView(shortName: context.attributes.awayTeam, longName: context.attributes.awayTeam, score: context.state.awayScore, isWinning: context.state.awayScore > context.state.homeScore, isAway: true, data: try? Data(contentsOf: fileURL))
                    } else {
                        IndividualTeamView(shortName: context.attributes.awayTeam, longName: context.attributes.awayTeam, score: -1, isWinning: context.state.awayScore > context.state.homeScore, isAway: true)
                    }
                    progressLabel(for: context.state)
                        .frame(maxWidth: .infinity, alignment: .center)
                    if let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(context.attributes.homeTeam) {
                        IndividualTeamView(shortName: context.attributes.homeTeam, longName: context.attributes.homeTeam, score: context.state.homeScore, isWinning: context.state.homeScore > context.state.awayScore, isAway: false, data: try? Data(contentsOf: fileURL))
                    } else {
                        IndividualTeamView(shortName: context.attributes.homeTeam, longName: context.attributes.homeTeam, score: context.state.homeScore, isWinning: context.state.homeScore > context.state.awayScore, isAway: false)
                    }
                }
                if let situation = context.state.situation {
                    LiveActivitySituationStrip(
                        situation: situation,
                        homeName: shortAbbreviation(short: context.attributes.homeTeamShort, full: context.attributes.homeTeam),
                        awayName: shortAbbreviation(short: context.attributes.awayTeamShort, full: context.attributes.awayTeam),
                        tint: WidgetTokens.inkSoft
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                if let lastPlay = context.state.lastPlay, !lastPlay.isEmpty {
                    Text(lastPlay)
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(WidgetTokens.inkSoft)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(16)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let race = context.state.race {
                        Label(race.session, systemImage: "flag.checkered")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(WidgetTokens.ink)
                    } else {
                    HStack {
                        badgeImage(for: context.attributes.awayTeam, size: 35)
                        VStack {
                            if context.state.awayScore > context.state.homeScore {
                                Text("\(context.state.awayScore)")
                                    .font(.system(size: 24))
                                    .fontWeight(.heavy)
                            } else {
                                Text("\(context.state.awayScore)")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                            }
                            Text(context.attributes.awayTeam)
                        }
                    }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.race != nil {
                        progressLabel(for: context.state)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.trailing, 6)
                    } else {
                    HStack {
                        VStack {
                            if context.state.awayScore < context.state.homeScore {
                                Text("\(context.state.homeScore)")
                                    .font(.system(size: 24))
                                    .fontWeight(.heavy)
                            } else {
                                Text("\(context.state.homeScore)")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                            }
                            Text(context.attributes.homeTeam)
                        }
                        badgeImage(for: context.attributes.homeTeam, size: 35)
                    }
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    if context.state.race == nil {
                        LiveAnimatedView()
                            .transition(.scale(scale: 2.5))
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    if let race = context.state.race {
                        VStack(spacing: 4) {
                            ForEach(race.leaders, id: \.position) { driver in
                                RaceLeaderRow(driver: driver, ink: WidgetTokens.ink)
                            }
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
                        Image(systemName: "flag.checkered")
                        Text(race.leaders.first?.code ?? race.session)
                    }
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundColor(WidgetTokens.ink)
                } else {
                Text(shortAbbreviation(short: context.attributes.awayTeamShort, full: context.attributes.awayTeam))
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundColor(WidgetTokens.ink)
                }
            } compactTrailing: {
                if let race = context.state.race {
                    Text(compactLap(context.state.progress, session: race.session))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundColor(WidgetTokens.ink)
                } else {
                Text("\(context.state.awayScore)-\(context.state.homeScore)")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundColor(WidgetTokens.ink)
                }
            } minimal: {
                if context.state.race != nil {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(WidgetTokens.ink)
                } else {
                // Same constraint as compact — use abbreviation text.
                Text(shortAbbreviation(short: context.attributes.awayTeamShort, full: context.attributes.awayTeam))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(WidgetTokens.ink)
                }
            }
        }
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
                                             situation: LiveActivitySituation(downDistance: "3rd & 4 at KC 12", possession: .away, redZone: true, homeWinPct: 58))
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
#endif
