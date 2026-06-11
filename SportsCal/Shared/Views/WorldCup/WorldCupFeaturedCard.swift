//
//  WorldCupFeaturedCard.swift
//  SportsCal
//
//  A prominent entry point to the World Cup hub, shown on the Games page. Self-gating:
//  appears during the tournament window or whenever World Cup matches are in the feed,
//  so it both promotes the tournament pre-launch and links to live action during it.
//

import SwiftUI
import SportsCalModel

struct WorldCupFeaturedCard: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @Environment(UserDefaultStorage.self) private var storage

    private var accent: Color { .app(.soccer) }

    /// Activation window — promote the hub through the run-up (matching the
    /// server's eager-fetch date) so the card is stable before the first match
    /// appears in the feed, not dependent on a momentarily-empty refresh.
    private static let windowStart = DateComponents(calendar: .current, year: 2026, month: 5, day: 15).date ?? .distantFuture
    private static let windowEnd = DateComponents(calendar: .current, year: 2026, month: 7, day: 20).date ?? .distantPast

    private var inWindow: Bool {
        let now = Date()
        return now >= Self.windowStart && now <= Self.windowEnd
    }

    private var hasGames: Bool { !viewModel.worldCupGamesWithTeams.isEmpty }
    private var liveCount: Int { viewModel.worldCupGamesWithTeams.filter { $0.game.strStatus == "in" }.count }

    var shouldShow: Bool { inWindow || hasGames }

    var body: some View {
        if shouldShow {
            NavigationLink {
                WorldCupHubView()
                    .environment(viewModel)
                    .environment(favorites)
                    .environment(storage)
            } label: {
                HStack(spacing: .appSpace3) {
                    ZStack {
                        Circle().fill(accent.opacity(0.15)).frame(width: 44, height: 44)
                        Image(systemName: "soccerball")
                            .font(.title3)
                            .foregroundStyle(accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FIFA World Cup 2026")
                            .font(.appHeadline)
                            .foregroundStyle(Color.appInk)
                        Text(subtitle)
                            .font(.appCaption)
                            .foregroundStyle(liveCount > 0 ? Color.appLive : Color.appInkSoft)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(Color.appInkFaint)
                }
                .appCard(fill: Color.appAlt)
            }
            .buttonStyle(.plain)
        }
    }

    private var subtitle: String {
        if liveCount > 0 { return "\(liveCount) match\(liveCount == 1 ? "" : "es") live now" }
        if hasGames { return "Schedule, groups & bracket" }
        return "Starts Jun 11 · Tap to follow"
    }
}
