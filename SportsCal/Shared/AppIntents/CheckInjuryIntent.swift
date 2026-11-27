//
//  CheckInjuryIntent.swift
//  SportsCal
//
//  Siri / Shortcuts / Spotlight: "When is Jock Landale back in Scoreline?"
//  Answers with the injury, the status and ESPN's estimated return.
//

import AppIntents
import SwiftUI
import SportsCalModel

/// A player on the NBA/NFL/NHL/MLB injury report.
struct InjuredPlayerEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Injured Player"
    static var defaultQuery = InjuredPlayerQuery()

    var id: String
    var name: String
    var team: String
    var headline: String

    init(_ injury: PlayerInjury) {
        id = injury.id
        name = injury.playerName
        team = injury.teamName
        headline = InjuryText.headline(injury)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(team) · \(headline)")
    }
}

struct InjuredPlayerQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [InjuredPlayerEntity] {
        await InjuryStore.shared.refreshIfStale(maxAge: 30 * 60)
        let byID = Dictionary(InjuryStore.shared.injuries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return identifiers.compactMap { byID[$0].map(InjuredPlayerEntity.init) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [InjuredPlayerEntity] {
        await InjuryStore.shared.refreshIfStale(maxAge: 30 * 60)
        return InjuryStore.shared.search(string).prefix(20).map(InjuredPlayerEntity.init)
    }

    /// Everyone on the report, the user's teams first: Siri matches spoken names
    /// against these.
    @MainActor
    func suggestedEntities() async throws -> [InjuredPlayerEntity] {
        await InjuryStore.shared.refreshIfStale(maxAge: 30 * 60)
        // Reads the same App Group store the app writes (team IDs, resolved by name).
        let favorites = Favorites()
        return InjuryStore.shared.injuries
            .sorted { lhs, rhs in
                let l = favorites.contains(lhs.teamName), r = favorites.contains(rhs.teamName)
                if l != r { return l }
                return lhs.playerName < rhs.playerName
            }
            .map(InjuredPlayerEntity.init)
    }
}

struct CheckInjuryIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Player Injury"
    static var description = IntentDescription(
        "What an NBA, NFL, NHL or MLB player is injured with, and when they're expected back.")

    @Parameter(title: "Player", requestValueDialog: "Which player?")
    var player: InjuredPlayerEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$player)'s injury")
    }

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        await InjuryStore.shared.refreshIfStale(maxAge: 30 * 60)
        guard let injury = InjuryStore.shared.injuries.first(where: { $0.id == player.id }) else {
            return .result(dialog: "\(player.name) isn't on the injury report anymore.") {
                EmptyView()
            }
        }
        return .result(dialog: IntentDialog(stringLiteral: InjuryText.answer(injury))) {
            InjurySnippetView(injury: injury)
        }
    }
}

/// The card Siri and Shortcuts show under the spoken answer.
struct InjurySnippetView: View {
    let injury: PlayerInjury

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InjuryRow(injury: injury, showsTeam: true)
            if let note = injury.summary ?? injury.details {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding()
    }
}
