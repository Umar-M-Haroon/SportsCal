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

struct LiveSportActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveSportActivityAttributes.self) { context in
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
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
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

                DynamicIslandExpandedRegion(.trailing) {
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
                
                DynamicIslandExpandedRegion(.center) {
                    LiveAnimatedView()
                        .transition(.scale(scale: 2.5))
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        progressLabel(for: context.state)
                            .frame(maxWidth: .infinity, alignment: .center)
                        if let lastPlay = context.state.lastPlay, !lastPlay.isEmpty {
                            Text(lastPlay)
                                .font(.system(.caption2, design: .rounded).weight(.medium))
                                .foregroundStyle(WidgetTokens.ink)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                
            } compactLeading: {
                // Apple's Dynamic Island compact slot tints raster images into
                // silhouettes (Apple HIG: "use SF Symbols, avoid complex images").
                // Use the team's short abbreviation instead — always legible,
                // never tinted, identifies the team at a glance. Real logos still
                // show in expanded and on the lock screen.
                Text(shortAbbreviation(short: context.attributes.awayTeamShort, full: context.attributes.awayTeam))
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundColor(WidgetTokens.ink)
            } compactTrailing: {
                Text("\(context.state.awayScore)-\(context.state.homeScore)")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundColor(WidgetTokens.ink)
            } minimal: {
                // Same constraint as compact — use abbreviation text.
                Text(shortAbbreviation(short: context.attributes.awayTeamShort, full: context.attributes.awayTeam))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(WidgetTokens.ink)
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
#endif
