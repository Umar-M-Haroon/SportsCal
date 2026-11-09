//
//  TennisDrawView.swift
//  SportsCal (iOS)
//
//  A tournament's singles draw as a bracket, one column per round, scrolled sideways
//  round by round. Built from the matches the app holds (`TennisDrawBracket`), so early
//  rounds of an older event can be partial. Followed players are starred and tinted.
//
//  Laid out on a fixed grid rather than measured: every column's slots sit at a known
//  pitch (doubling each round), so a column's match is centred on its two feeders and
//  the connectors are drawn straight from that arithmetic. A Slam's 127 matches are
//  plain fixed-size cards, with no geometry readers or preferences to resolve.
//

import SwiftUI
import SportsCalModel

struct TennisDrawView: View {
    let tournamentName: String
    /// The tournament's matches, as the hub was handed them.
    let games: [Game]
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites

    @State private var selectedTour: Leagues?
    @State private var focusedRound: String?

    @ScaledMetric(relativeTo: .caption) private var cardHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .caption) private var cardWidth: CGFloat = 200
    private let rowGap: CGFloat = 8
    private let connectorWidth: CGFloat = 18

    init(tournamentName: String, games: [Game], tour: Leagues? = nil) {
        self.tournamentName = tournamentName
        self.games = games
        _selectedTour = State(initialValue: tour)
    }

    // MARK: Derived

    private var toursPresent: [Leagues] {
        let set = Set(games.flatMap { $0.tennisTours })
        return [Leagues.atp, .wta].filter { set.contains($0) }
    }

    private var tour: Leagues? {
        guard toursPresent.count > 1 else { return nil }
        return selectedTour ?? toursPresent.first
    }

    private var bracket: TennisDrawBracket {
        let current = TournamentHubView.withLiveScores(games, live: viewModel.liveEventsForSport(.tennis))
        return TennisDrawBracket(games: TennisDrawBracket.singles(current, tour: tour))
    }

    /// The round to open on: the first with a match in play, else the first not yet
    /// finished, else the final.
    private func openingRound(_ bracket: TennisDrawBracket) -> String? {
        let rounds = bracket.rounds
        if let live = rounds.first(where: { $0.slots.contains { $0?.isTennisMatchLive == true } }) { return live.id }
        if let open = rounds.first(where: { $0.slots.contains { $0.map { !$0.isTennisMatchOver } ?? false } }) { return open.id }
        return rounds.last?.id
    }

    // MARK: Body

    var body: some View {
        let bracket = bracket
        VStack(spacing: 0) {
            if toursPresent.count > 1 {
                Picker("Tour", selection: Binding(
                    get: { tour ?? .atp },
                    set: { selectedTour = $0; focusedRound = nil }
                )) {
                    Text("Men's").tag(Leagues.atp)
                    Text("Women's").tag(Leagues.wta)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            if bracket.rounds.isEmpty {
                ContentUnavailableView("No Draw Yet", systemImage: "trophy",
                                       description: Text("The singles draw appears once its matches are scheduled."))
            } else {
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        roundPicker(bracket, proxy: proxy)
                        Divider()
                        ScrollView([.horizontal, .vertical]) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(Array(bracket.rounds.enumerated()), id: \.element.id) { index, round in
                                    column(round, index: index, bracket: bracket)
                                        .id(round.id)
                                    if index < bracket.rounds.count - 1 {
                                        connectors(from: round, index: index)
                                    }
                                }
                            }
                            .padding(16)
                        }
                        .onAppear {
                            guard let opening = openingRound(bracket) else { return }
                            focusedRound = opening
                            proxy.scrollTo(opening, anchor: .topLeading)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(tournamentName) Draw")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Round picker

    private func roundPicker(_ bracket: TennisDrawBracket, proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(bracket.rounds) { round in
                    let isFocused = focusedRound == round.id
                    Button {
                        focusedRound = round.id
                        withAnimation { proxy.scrollTo(round.id, anchor: .topLeading) }
                    } label: {
                        Text(round.shortLabel)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(isFocused ? Color.app(.tennis).opacity(0.2) : Color.gray.opacity(0.12))
                            )
                            .overlay(Capsule().strokeBorder(isFocused ? Color.app(.tennis) : .clear, lineWidth: 1.5))
                            .foregroundStyle(isFocused ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(round.name)
                    .accessibilityAddTraits(isFocused ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: Grid

    /// Distance between slot centres in column `index`.
    private func pitch(_ index: Int) -> CGFloat {
        (cardHeight + rowGap) * CGFloat(1 << index)
    }

    /// Centre of slot `slot` in column `index`, from the top of the grid.
    private func centerY(column index: Int, slot: Int) -> CGFloat {
        (CGFloat(slot) + 0.5) * pitch(index) - rowGap / 2
    }

    private func column(_ round: TennisDrawBracket.Round, index: Int, bracket: TennisDrawBracket) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(round.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(height: 20, alignment: .bottom)
                .padding(.bottom, 8)
            VStack(spacing: pitch(index) - cardHeight) {
                ForEach(Array(round.slots.enumerated()), id: \.offset) { slot, game in
                    if let game {
                        matchCard(game)
                    } else {
                        emptySlot(isBye: bracket.isBye(round: index, slot: slot))
                    }
                }
            }
            .padding(.top, centerY(column: index, slot: 0) - cardHeight / 2)
        }
        .frame(width: cardWidth)
    }

    /// The bracket lines from each pair of slots in `round` to the slot they feed.
    private func connectors(from round: TennisDrawBracket.Round, index: Int) -> some View {
        let slots = round.slots
        let headerHeight: CGFloat = 28
        let height = headerHeight + CGFloat(slots.count) * pitch(index)
        return Canvas { context, size in
            var path = Path()
            let middle = size.width / 2
            for parent in 0..<(slots.count / 2) where slots[parent * 2] != nil || slots[parent * 2 + 1] != nil {
                let top = headerHeight + centerY(column: index, slot: parent * 2)
                let bottom = headerHeight + centerY(column: index, slot: parent * 2 + 1)
                path.move(to: CGPoint(x: 0, y: top))
                path.addLine(to: CGPoint(x: middle, y: top))
                path.addLine(to: CGPoint(x: middle, y: bottom))
                path.addLine(to: CGPoint(x: 0, y: bottom))
                path.move(to: CGPoint(x: middle, y: (top + bottom) / 2))
                path.addLine(to: CGPoint(x: size.width, y: (top + bottom) / 2))
            }
            context.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: 1)
        }
        .frame(width: connectorWidth, height: height)
        .accessibilityHidden(true)
    }

    // MARK: Cards

    private func emptySlot(isBye: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .overlay {
                if isBye {
                    Text("Bye")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .accessibilityElement()
            .accessibilityLabel(isBye ? "Bye" : "To be decided")
    }

    private func matchCard(_ game: Game) -> some View {
        let followed = favorites.containsPlayer(game.strHomeTeam) || favorites.containsPlayer(game.strAwayTeam)
        let isLive = game.isTennisMatchLive
        return NavigationLink {
            TennisMatchDetailView(game: game)
                .environment(viewModel)
                .environment(favorites)
        } label: {
            VStack(spacing: 0) {
                playerLine(game, side: .home)
                Divider()
                playerLine(game, side: .away)
            }
            .padding(.horizontal, 8)
            .frame(width: cardWidth, height: cardHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(followed ? Color.yellow.opacity(0.12) : Color.secondaryGroupedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isLive ? Color.red.opacity(0.7) : (followed ? Color.yellow.opacity(0.6) : .clear),
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardLabel(game, followed: followed))
        .accessibilityHint("Opens the match")
    }

    private func playerLine(_ game: Game, side: GameSituation.Side) -> some View {
        let name = side == .home ? game.strHomeTeam : game.strAwayTeam
        let seed = side == .home ? game.tennisHomeSeed : game.tennisAwaySeed
        let winner = game.tennisMatchWinner
        let lost = winner != nil && winner != side
        return HStack(spacing: 4) {
            if favorites.containsPlayer(name) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }
            if game.tennisServer == side {
                TennisServeDot()
            }
            Text(Self.shortName(name))
                .font(.caption.weight(winner == side ? .bold : .regular))
                .foregroundStyle(lost ? .secondary : .primary)
                .lineLimit(1)
            if let seed {
                Text("\(seed)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            trailing(game, side: side)
        }
        .frame(maxHeight: .infinity)
    }

    /// The set scores once there are any; before that, the start time on the top line.
    @ViewBuilder
    private func trailing(_ game: Game, side: GameSituation.Side) -> some View {
        let sets = game.tennisSets
        if !sets.isEmpty {
            HStack(spacing: 5) {
                ForEach(Array(sets.enumerated()), id: \.offset) { _, set in
                    Text(set.text(for: side))
                        .fontWeight(set.winner == side ? .semibold : .regular)
                        .foregroundStyle(set.winner == side || !set.isComplete ? .primary : .secondary)
                }
            }
            .font(.caption.monospacedDigit())
        } else if side == .home, let date = game.standardDate, !game.isTennisMatchOver {
            Text(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if side == .away, let marker = game.tennisResultMarker {
            Text(marker)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func cardLabel(_ game: Game, followed: Bool) -> String {
        var parts = ["\(game.strHomeTeam) versus \(game.strAwayTeam)"]
        if game.isTennisMatchLive { parts.append("live") }
        parts += TennisMatchPresentation.spokenScore(game)
        if game.tennisSets.isEmpty, let date = game.standardDate {
            parts.append(date.formatted(.dateTime.weekday(.wide).hour().minute()))
        }
        if followed { parts.append("following") }
        return parts.joined(separator: ", ")
    }

    /// "C. Alcaraz"; doubles pairs and TBD as they are.
    static func shortName(_ name: String) -> String {
        guard !name.contains("/"), name != "TBD" else { return name }
        let parts = name.split(separator: " ")
        guard parts.count >= 2, let first = parts.first?.first else { return name }
        return "\(first). \(parts.dropFirst().joined(separator: " "))"
    }
}

#Preview {
    @Previewable @State var favorites = Favorites()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())

    func match(_ id: String, _ round: String, _ home: Int, _ away: Int, _ names: (String, String),
               day: Int, h: [Double]? = nil, a: [Double]? = nil, status: String = "post") -> Game {
        Game(idEvent: id, idLeague: "\(Leagues.atp.rawValue)", idHomeTeam: "\(home)", idAwayTeam: "\(away)",
             strHomeTeam: names.0, strAwayTeam: names.1, strStatus: status,
             strTimestamp: "2026-11-0\(day)T13:00:00Z", homeLinescores: h, awayLinescores: a, isoDate: nil,
             tournamentName: "Paris Masters", round: round, drawSlug: "mens-singles")
    }

    let games: [Game] = [
        match("f", "Final", 1, 8, ("Carlos Alcaraz", "Ben Shelton"), day: 8, status: "pre"),
        match("sf1", "Semifinal", 1, 4, ("Carlos Alcaraz", "Casper Ruud"), day: 7, h: [6, 6], a: [3, 4]),
        match("sf2", "Semifinal", 5, 8, ("Botic van de Zandschulp", "Ben Shelton"), day: 7, h: [4, 6], a: [6, 7]),
        match("qf1", "Quarterfinal", 1, 2, ("Carlos Alcaraz", "Taylor Fritz"), day: 6, h: [7, 6], a: [6, 3]),
        match("qf2", "Quarterfinal", 3, 4, ("Nuno Borges", "Casper Ruud"), day: 6, h: [3, 4], a: [6, 6]),
        match("qf3", "Quarterfinal", 5, 6, ("Botic van de Zandschulp", "Rei Hijikata"), day: 6, h: [6, 6], a: [2, 1]),
        match("qf4", "Quarterfinal", 7, 8, ("Tommy Paul", "Ben Shelton"), day: 6, h: [4, 3], a: [6, 6]),
    ]

    return NavigationStack {
        TennisDrawView(tournamentName: "Paris Masters", games: games)
            .environment(viewModel)
            .environment(favorites)
    }
}
