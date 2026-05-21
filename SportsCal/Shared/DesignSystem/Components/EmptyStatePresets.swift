//
//  EmptyStatePresets.swift
//  SportsCal — Design System v1.0 (Phase E)
//
//  Catalog of empty-state configurations for the 12 wireframed scenarios
//  + a few production cases. Each preset is a static factory on
//  EmptyStateView so call sites read like
//  `EmptyStateView.quietDay(onPeekTomorrow: { ... })`.
//
//  Symbols + copy are pre-tuned per scenario; pass actions in for any
//  CTAs that need them.
//

import SwiftUI
import SportsCalModel

public extension EmptyStateView {

    // MARK: - 1. First launch — handled by OnboardingPage; preset for parity.
    static func firstLaunch(onPickFavorites: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            symbol: "star.bubble",
            headline: "Pick a few teams",
            message: "We'll start you with games from the teams you follow. Add more anytime from Browse.",
            cta: CTA(label: "Pick favorites", action: onPickFavorites)
        )
    }

    // MARK: - 2. Quiet day — no games scheduled at all.
    static func quietDay(tomorrowCount: Int? = nil, onPeekTomorrow: (() -> Void)? = nil) -> EmptyStateView {
        let body: String = {
            if let n = tomorrowCount, n > 0 {
                return "Quiet day. Tomorrow has \(n) game\(n == 1 ? "" : "s") lined up — peek ahead?"
            }
            return "No games on the board today. Check Browse to see what's coming up this week."
        }()
        return EmptyStateView(
            symbol: "sportscourt",
            headline: "Quiet day",
            message: body,
            cta: onPeekTomorrow.map { CTA(label: "Tomorrow's games", action: $0) }
        )
    }

    // MARK: - 3. No favorites set — has games, but the user hasn't picked teams.
    static func noFavorites(onPickFavorites: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            symbol: "heart.slash",
            headline: "No favorites yet",
            message: "Add teams to your favorites to surface their games at the top.",
            cta: CTA(label: "Pick favorites", action: onPickFavorites)
        )
    }

    // MARK: - 4. Favorites idle — your teams aren't playing today, but other games are.
    static func favoritesIdle(otherGameCount: Int, onShowAll: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            symbol: "clock.badge.questionmark",
            headline: "Your teams have the day off",
            message: "But there are \(otherGameCount) other game\(otherGameCount == 1 ? "" : "s") on tap. Want to peek?",
            cta: CTA(label: "Show all games", action: onShowAll)
        )
    }

    // MARK: - 5. All pre-game — countdown to first kickoff.
    static func allPreGame(firstKickoff: String) -> EmptyStateView {
        EmptyStateView(
            symbol: "clock.arrow.circlepath",
            headline: "Tipoff at \(firstKickoff)",
            message: "Nothing live yet — first game starts shortly. We'll surface it the moment it goes live."
        )
    }

    // MARK: - 6. All final — recap mode.
    static func allFinal(count: Int) -> EmptyStateView {
        EmptyStateView(
            symbol: "trophy",
            headline: "All wrapped up",
            message: "All \(count) game\(count == 1 ? "" : "s") on the slate are final. Tap a card below to see results."
        )
    }

    // MARK: - 8. Off-season per sport.
    static func offSeason(_ sport: SportType, returnsIn: String? = nil) -> EmptyStateView {
        let suffix: String = {
            if let returnsIn { return "\(sport.displayName) returns in \(returnsIn)." }
            return "\(sport.displayName) is on break — we'll fire it back up when the season starts."
        }()
        return EmptyStateView(
            symbol: "moon.zzz",
            headline: "\(sport.displayName) · off-season",
            message: suffix
        )
    }

    // MARK: - 9. Postponed / rain delay — when used at the screen level
    //         (per-row uses DegradedSectionPlaceholder).
    static func postponed(matchup: String, reason: String? = nil) -> EmptyStateView {
        let body = reason ?? "The game has been postponed. We'll update once the league sets a new time."
        return EmptyStateView(
            symbol: "cloud.rain",
            headline: "\(matchup) · postponed",
            message: body
        )
    }

    // MARK: - 10. Connection lost — no cache available.
    static func connectionLost(onRetry: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            symbol: "wifi.slash",
            headline: "Offline",
            message: "We can't reach the scores feed right now. Check your connection and try again.",
            cta: CTA(label: "Retry", action: onRetry)
        )
    }

    // MARK: - 12. Tip-off transition — used as a brief overlay/inline pill,
    //          NOT a full empty state. Provided here for catalog completeness;
    //          call sites use the TipoffPill view in the same file.
    //          (Skipped from EmptyStateView — see TipoffPill below.)

    // MARK: - Production extras

    static func searchEmpty(query: String) -> EmptyStateView {
        EmptyStateView(
            symbol: "magnifyingglass",
            headline: "No matches",
            message: "We didn't find anything for \"\(query)\". Try a team name or league."
        )
    }

    static func filterEmpty(disabledSports: [SportType], onReenable: @escaping () -> Void) -> EmptyStateView {
        let names = disabledSports.map(\.displayName).joined(separator: ", ")
        return EmptyStateView(
            symbol: "line.3.horizontal.decrease.circle",
            headline: "All filtered out",
            message: "Today's games are in sports you've turned off (\(names)). Re-enable to see them.",
            cta: CTA(label: "Re-enable", action: onReenable)
        )
    }

    static func suspendedInProgress(matchup: String, sinceLabel: String) -> EmptyStateView {
        EmptyStateView(
            symbol: "exclamationmark.triangle",
            headline: "\(matchup) · suspended",
            message: "Play has been halted since \(sinceLabel). We'll resume scoring once it picks back up."
        )
    }

    static func apiError(onRetry: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            symbol: "wifi.exclamationmark",
            headline: "Something went sideways",
            message: "The scores feed returned an error. We'll retry automatically — or kick it off now.",
            cta: CTA(label: "Retry now", action: onRetry)
        )
    }

    static func watchReachabilityLost() -> EmptyStateView {
        EmptyStateView(
            symbol: "iphone.gen3.slash",
            headline: "Open SportsCal on iPhone",
            message: "Your watch can't reach your phone. Open the iPhone app to refresh."
        )
    }
}

// MARK: - Tip-off transition pill

/// Small badge that flashes for ~5 seconds when a game's state flips
/// `.pre → .live`. Use as an overlay or inline tag on the row that just
/// went live.
public struct TipoffPill: View {
    public init() {}

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.circle.fill")
                .imageScale(.small)
            Text("TIP-OFF")
                .font(.appFootnote)
                .tracking(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(Color.appBackground)
        .background(
            Capsule().fill(Color.appLive)
        )
        .scaleEffect(pulse ? 1.06 : 1.0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatCount(6, autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel(Text("Game just went live"))
    }
}
