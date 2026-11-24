//
//  MenuBarLabel.swift
//  SportsCal
//

#if os(macOS)
import SwiftUI
import SportsCalModel

// MARK: - Preferences

/// Which live games the menu bar label rotates through (Settings › General › Menu Bar).
enum MenuBarRotation: String, CaseIterable, Identifiable {
    case favoritesThenAll
    case allLive
    case favoritesOnly
    case followed
    case iconOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favoritesThenAll: "Favorites, then all live games"
        case .allLive: "All live games"
        case .favoritesOnly: "Favorite teams only"
        case .followed: "Followed games only"
        case .iconOnly: "Just the icon"
        }
    }
}

/// What the label shows when there's nothing to rotate through.
enum MenuBarIdleDisplay: String, CaseIterable, Identifiable {
    case nextFavorite
    case todayCount
    case icon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nextFavorite: "Countdown to your next favorite"
        case .todayCount: "Number of games today"
        case .icon: "Just the icon"
        }
    }
}

enum MenuBarPrefs {
    static let rotationKey = "menuBar.rotation"
    static let intervalKey = "menuBar.interval"
    static let idleKey = "menuBar.whenIdle"
    static let showsClockKey = "menuBar.showsClock"
    static let followedKey = "menuBar.followedGameIDs"
    static let pinnedKey = "menuBar.pinnedGameID"

    static let intervals: [Double] = [3, 5, 10, 20, 30]
}

/// Games followed for the menu bar: the Mac's "Follow", since it has no Live
/// Activities. Stored as comma-separated game ids in `menuBar.followedGameIDs`.
enum MenuBarFollows {
    /// Older follows fall off past this; finished games never rotate anyway.
    private static let limit = 50

    static func ids(_ raw: String) -> [String] {
        raw.split(separator: ",").map(String.init)
    }

    static func contains(_ id: String, in raw: String) -> Bool {
        ids(raw).contains(id)
    }

    static func toggled(_ id: String, in raw: String) -> String {
        var list = ids(raw)
        if let index = list.firstIndex(of: id) {
            list.remove(at: index)
        } else {
            list.append(id)
        }
        return list.suffix(limit).joined(separator: ",")
    }

    /// The live games the label rotates through for `rotation`. A pinned live game
    /// takes the label to itself (unless the label is set to the icon).
    static func rotatingGames(
        rotation: MenuBarRotation,
        live: [GameWithTeams],
        isFavorite: (Game) -> Bool,
        followedRaw: String,
        pinnedID: String
    ) -> [GameWithTeams] {
        if rotation == .iconOnly { return [] }
        if !pinnedID.isEmpty, let pinned = live.first(where: { $0.game.id == pinnedID }) {
            return [pinned]
        }
        switch rotation {
        case .iconOnly:
            return []
        case .allLive:
            return live
        case .favoritesOnly:
            return live.filter { isFavorite($0.game) }
        case .favoritesThenAll:
            let favorites = live.filter { isFavorite($0.game) }
            return favorites.isEmpty ? live : favorites
        case .followed:
            let followed = Set(ids(followedRaw))
            return live.filter { followed.contains($0.game.id) }
        }
    }
}

// MARK: - Label

struct MenuBarLabel: View {
    /// Already filtered and ordered by `MenuBarFollows.rotatingGames`.
    let games: [GameWithTeams]
    let upcomingFavorite: GameWithTeams?
    let todayCount: Int
    let interval: Double
    let idleDisplay: MenuBarIdleDisplay
    let showsClock: Bool

    @State private var tick = 0
    /// Drives the countdown. The label only redraws when its inputs change, so
    /// without this "in 20m" stays frozen until the next schedule refresh.
    @State private var now = Date()

    var body: some View {
        content
            // Only ticks while there's more than one game to show, so an idle menu
            // bar costs nothing.
            .task(id: RotationKey(interval: interval, rotates: games.count > 1)) {
                guard games.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(max(interval, 1)))
                    if Task.isCancelled { break }
                    tick += 1
                }
            }
            // Ticks once a minute, on the minute, only while a countdown is showing.
            .task(id: showsCountdown) {
                guard showsCountdown else { return }
                while !Task.isCancelled {
                    now = Date()
                    let intoMinute = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
                    try? await Task.sleep(for: .seconds(60 - intoMinute + 0.05))
                }
            }
    }

    private var showsCountdown: Bool {
        games.isEmpty && idleDisplay == .nextFavorite && upcomingFavorite != nil
    }

    private struct RotationKey: Equatable {
        let interval: Double
        let rotates: Bool
    }

    // The menu bar draws a label's first Text (and Image) only, so each state is a
    // single Text with any symbol interpolated into it.
    @ViewBuilder
    private var content: some View {
        if !games.isEmpty {
            Text(liveText(games[tick % games.count]))
                .monospacedDigit()
        } else if idleDisplay == .nextFavorite, let upcoming = upcomingFavorite,
                  let gameDate = upcoming.game.standardDate, gameDate > now {
            Text(upcomingText(upcoming, gameDate: gameDate))
                .monospacedDigit()
        } else if idleDisplay != .icon, todayCount > 0 {
            Text("\(Image(systemName: "sportscourt.fill")) \(todayCount)")
                .monospacedDigit()
        } else {
            Image(systemName: "sportscourt.fill")
        }
    }

    private func liveText(_ gwt: GameWithTeams) -> String {
        let game = gwt.game
        var text: String
        if game.isIndividualSport {
            let name = Team.shortCode(strTeamShort: gwt.homeTeam?.strTeamShort, name: game.strHomeTeam, idTeam: gwt.homeTeam?.idTeam)
            if let leader = game.resolvedLeaderboard.first {
                text = "\(name) \(leader.score)"
            } else {
                text = name
            }
        } else {
            let awaySeed = game.awaySeed.map { "(\($0)) " } ?? ""
            let homeSeed = game.homeSeed.map { "(\($0)) " } ?? ""
            let away = awaySeed + Team.shortCode(strTeamShort: gwt.awayTeam?.strTeamShort, name: game.strAwayTeam, idTeam: gwt.awayTeam?.idTeam)
            let home = homeSeed + Team.shortCode(strTeamShort: gwt.homeTeam?.strTeamShort, name: game.strHomeTeam, idTeam: gwt.homeTeam?.idTeam)
            if let awayScore = game.compactScore(home: false), let homeScore = game.compactScore(home: true) {
                text = "\(away) \(awayScore) - \(home) \(homeScore)"
            } else {
                text = "\(away) @ \(home)"
            }
        }
        if showsClock, let status = game.displayStatus, !status.isEmpty {
            text += " · \(status)"
        }
        return text
    }

    private func upcomingText(_ gwt: GameWithTeams, gameDate: Date) -> String {
        let remaining = gameDate.timeIntervalSince(now)
        let name = Team.shortCode(strTeamShort: gwt.homeTeam?.strTeamShort, name: gwt.game.strHomeTeam, idTeam: gwt.homeTeam?.idTeam)
        if remaining > 6 * 3600 {
            return "⭑ \(name) \(Self.shortTimeFormatter.string(from: gameDate))"
        }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        return hours > 0 ? "⭑ \(name) in \(hours)h \(minutes)m" : "⭑ \(name) in \(minutes)m"
    }

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "a"
        f.pmSymbol = "p"
        return f
    }()
}

// MARK: - Pro marking

/// The menu bar's live scores are Pro. Free users see a "Pro" badge on its
/// settings and follow button, and either opens the paywall.
enum MenuBarPro {
    /// Brings the main window forward and asks ContentView for the paywall
    /// (the Settings window and the menu bar have no paywall of their own).
    static func requestPaywall() {
        NSApp.activate(ignoringOtherApps: true)
        UpsellCoordinator.shared.noteDirectOpen(.menuBar)
        NotificationCenter.default.post(name: .requestPaywall, object: nil)
    }
}

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.appAccent))
            .accessibilityLabel("Scoreline Pro")
    }
}

// MARK: - Follow button (game and race pages)

/// "Menu Bar" in a Mac game page's action row: follows the game so the label
/// shows it while live ("Followed games only"). Pro, like the label; a free user
/// sees it with a Pro badge and gets the paywall.
struct MenuBarFollowButton: View {
    let game: Game
    @AppStorage(MenuBarPrefs.followedKey) private var followedRaw = ""
    @Environment(SubscriptionManager.self) private var subscriptionManager

    var body: some View {
        if !isGameCompleted(game) {
            let isPro = subscriptionManager.isPro
            let isFollowing = isPro && MenuBarFollows.contains(game.id, in: followedRaw)
            Button {
                if isPro {
                    followedRaw = MenuBarFollows.toggled(game.id, in: followedRaw)
                } else {
                    MenuBarPro.requestPaywall()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: isFollowing ? "menubar.rectangle" : "menubar.arrow.up.rectangle")
                        .font(.title3)
                        .foregroundColor(isFollowing ? .appAccent : .secondary)
                        .overlay(alignment: .topTrailing) {
                            if !isPro { ProBadge().offset(x: 16, y: -6) }
                        }
                    Text(isFollowing ? "In Menu Bar" : "Menu Bar")
                        .font(.caption2)
                        .foregroundColor(isFollowing ? .appAccent : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .help(!isPro ? "Live scores in the menu bar are part of Scoreline Pro"
                  : isFollowing ? "Stop following in the menu bar" : "Follow this game in the menu bar")
        }
    }
}

// MARK: - Settings

/// Settings › General › Menu Bar.
struct MenuBarSettingsSection: View {
    @AppStorage(MenuBarPrefs.rotationKey) private var rotation: MenuBarRotation = .favoritesThenAll
    @AppStorage(MenuBarPrefs.intervalKey) private var interval: Double = 5
    @AppStorage(MenuBarPrefs.idleKey) private var idle: MenuBarIdleDisplay = .nextFavorite
    @AppStorage(MenuBarPrefs.showsClockKey) private var showsClock = true
    @AppStorage(MenuBarPrefs.followedKey) private var followedRaw = ""
    @Environment(SubscriptionManager.self) private var subscriptionManager

    var body: some View {
        let isPro = subscriptionManager.isPro
        Section {
            if !isPro {
                HStack {
                    Text("Live scores in your menu bar are part of Scoreline Pro.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Upgrade…") { MenuBarPro.requestPaywall() }
                        .buttonStyle(.borderedProminent)
                }
            }
            Group {
                Picker("Show", selection: $rotation) {
                    ForEach(MenuBarRotation.allCases) { Text($0.title).tag($0) }
                }
                if rotation != .iconOnly {
                    Picker("Switch games every", selection: $interval) {
                        ForEach(MenuBarPrefs.intervals, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                    }
                    Toggle("Show the game clock", isOn: $showsClock)
                    Picker("When nothing's live", selection: $idle) {
                        ForEach(MenuBarIdleDisplay.allCases) { Text($0.title).tag($0) }
                    }
                }
                if rotation == .followed, !followedRaw.isEmpty {
                    Button("Unfollow All Games") { followedRaw = "" }
                }
            }
            .disabled(!isPro)
        } header: {
            HStack(spacing: 6) {
                Text("Menu Bar")
                ProBadge()
            }
        } footer: {
            Text(footer(isPro: isPro))
        }
    }

    private func footer(isPro: Bool) -> String {
        if !isPro { return "Without Pro, the menu bar shows only the Scoreline icon." }
        if rotation == .followed {
            return "Follow a game with Menu Bar on its page, or right-click it in the menu bar list. A pinned game always shows."
        }
        return "A game pinned from the menu bar list always shows on its own."
    }
}
#endif
