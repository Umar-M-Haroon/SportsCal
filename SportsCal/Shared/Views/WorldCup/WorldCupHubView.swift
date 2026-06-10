//
//  WorldCupHubView.swift
//  SportsCal
//
//  The featured "FIFA World Cup 2026" destination: live/upcoming matches, group
//  standings (12 groups), the knockout bracket, and the Golden Boot race. Reuses
//  existing game-detail navigation and the shared standings table.
//

import SwiftUI
import SportsCalModel
#if os(iOS)
import EventKit
#endif

struct WorldCupHubView: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @Environment(UserDefaultStorage.self) private var storage

    @State private var model = WorldCupHubViewModel()
    @State private var sheetType: SheetType? = nil
    @State private var shouldShowProAlert: Bool = false

    @AppStorage("shouldShowWorldCup") private var shouldShowWorldCup: Bool = false
    @AppStorage("shouldShowSoccer") private var shouldShowSoccer: Bool = false

    private var accent: Color { .app(.soccer) }
    private var isEnabled: Bool { shouldShowWorldCup || shouldShowSoccer }

    private var allGames: [GameWithTeams] { viewModel.worldCupGamesWithTeams }
    private var liveGames: [GameWithTeams] { allGames.filter { $0.game.strStatus == "in" } }
    private var upcomingGames: [GameWithTeams] {
        let now = Date()
        return allGames.filter { gwt in
            gwt.game.strStatus != "in" && !isGameCompleted(gwt.game) &&
            (gwt.game.standardDate ?? .distantFuture) >= now
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .appSpace5) {
                header
                if !isEnabled { enableCTA }
                WorldCupFollowButton()

                if !liveGames.isEmpty {
                    section("LIVE NOW") {
                        ForEach(liveGames) {
                            WorldCupMatchRow(gameWithTeams: $0, sheetType: $sheetType, shouldShowSportsCalProAlert: $shouldShowProAlert)
                        }
                    }
                }

                if !upcomingGames.isEmpty {
                    section("UPCOMING") {
                        ForEach(Array(upcomingGames.prefix(8))) {
                            WorldCupMatchRow(gameWithTeams: $0, sheetType: $sheetType, shouldShowSportsCalProAlert: $shouldShowProAlert)
                        }
                    }
                }

                if model.hasBracket, let bracket = model.bracket {
                    section("KNOCKOUT BRACKET") {
                        NavigationLink {
                            bracketScreen(bracket)
                        } label: {
                            HStack {
                                Label("View full bracket", systemImage: "trophy")
                                    .font(.appCallout)
                                    .foregroundStyle(accent)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Color.appInkFaint)
                            }
                            .appCard(fill: Color.appAlt)
                        }
                        .buttonStyle(.plain)
                    }
                }

                groupsSection

                if !model.scorers.isEmpty {
                    section("GOLDEN BOOT") {
                        WorldCupScorersView(scorers: Array(model.scorers.prefix(5)))
                            .appCard(fill: Color.appAlt)
                        if model.scorers.count > 5 {
                            NavigationLink {
                                WorldCupScorersScreen(scorers: model.scorers)
                            } label: {
                                Text("See all scorers")
                                    .font(.appCaption)
                                    .foregroundStyle(accent)
                            }
                        }
                    }
                }

                if isEnabled && allGames.isEmpty && model.groups.isEmpty && !model.hasBracket {
                    Text("No World Cup matches scheduled right now. Check back closer to kickoff on June 11, 2026.")
                        .font(.appCaption)
                        .foregroundStyle(Color.appInkSoft)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, .appSpace5)
                }
            }
            .padding(.appSpace4)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("World Cup 2026")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .task { await model.load(from: viewModel) }
        .refreshable { await model.load(from: viewModel) }
        .alert("Scoreline Pro", isPresented: $shouldShowProAlert) {
            Button("Subscribe") { sheetType = .paywall }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This feature requires Scoreline Pro")
        }
        .sheet(item: $sheetType) { sheet in
            switch sheet {
            case .paywall:
                SubscriptionSheet(subscriptionPresented: .constant(true))
            #if os(iOS)
            case .calendar(let game):
                if let game { makeCalendarEvent(game: game) }
            #endif
            default:
                EmptyView()
            }
        }
    }

    #if os(iOS)
    private func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        event.title = "\(game.strAwayTeam) @ \(game.strHomeTeam)"
        if let gameDate = game.standardDate {
            event.startDate = gameDate
            event.endDate = gameDate.afterHoursFromNow(hours: 2)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            HStack(spacing: .appSpace2) {
                Image(systemName: "soccerball")
                    .font(.title2)
                    .foregroundStyle(accent)
                Text("FIFA World Cup 2026")
                    .font(.appTitle)
                    .foregroundStyle(Color.appInk)
            }
            Text("Jun 11 – Jul 19, 2026 · USA · Canada · Mexico")
                .font(.appCaption)
                .foregroundStyle(Color.appInkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var enableCTA: some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            Text("Follow every match, group table, and the road to the final — without turning on all of soccer.")
                .font(.appCaption)
                .foregroundStyle(Color.appInkSoft)
            Button {
                shouldShowWorldCup = true
                viewModel.filterSports(force: true)
            } label: {
                Label("Enable World Cup", systemImage: "plus.circle.fill")
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .appSpace2)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .appCard(fill: Color.appAlt)
    }

    @ViewBuilder
    private var groupsSection: some View {
        if model.standingsLoading && model.groups.isEmpty {
            section("GROUPS") {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, .appSpace3)
            }
        } else if !model.groups.isEmpty {
            section("GROUPS") {
                ForEach(Array(model.groups.enumerated()), id: \.offset) { _, child in
                    if let entries = child.standings?.entries, !entries.isEmpty {
                        StandingsGroupView(name: child.name, entries: entries, isSoccer: true, accent: accent)
                            .appCard(fill: Color.appAlt)
                    }
                }
            }
        }
    }

    private func bracketScreen(_ bracket: WorldCupBracket) -> some View {
        WorldCupBracketView(bracket: bracket)
            .environment(viewModel)
            .environment(favorites)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Bracket")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: .appSpace3) {
            Text(title).appEyebrow().foregroundStyle(accent)
            content()
        }
    }
}
