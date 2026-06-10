//
//  WorldCupHubViewModel.swift
//  SportsCal
//
//  Backs WorldCupHubView. Bracket + Golden Boot ride along on the main schedule
//  (`GameViewModel.worldCup`) so they're usually free; group standings are fetched
//  from the existing `/standings/4429` route. Routes are used only as a fallback.
//

import SwiftUI
import SportsCalModel

@MainActor
@Observable
final class WorldCupHubViewModel {
    var standing: Standing?
    var bracket: WorldCupBracket?
    var scorers: [WorldCupScorer] = []
    var standingsLoading = false
    var standingsError: String?

    private let worldCupLeagueID = String(Leagues.FIFA_World_Cup.rawValue)

    func load(from viewModel: GameViewModel) async {
        // Seed from the ridealong enrichment first (zero network).
        if let wc = viewModel.worldCup {
            if let b = wc.bracket { bracket = b }
            if !wc.topScorers.isEmpty { scorers = wc.topScorers }
        }
        await loadStandings()
        await loadBracketIfNeeded()
        await loadScorersIfNeeded()
    }

    func loadStandings() async {
        standingsLoading = true
        standingsError = nil
        defer { standingsLoading = false }
        do {
            standing = try await NetworkHandler.getStandings(for: worldCupLeagueID)
        } catch {
            standingsError = error.localizedDescription
        }
    }

    private func loadBracketIfNeeded() async {
        if let b = bracket, !b.isEmpty { return }
        if let fetched = try? await NetworkHandler.getWorldCupBracket(), !fetched.isEmpty {
            bracket = fetched
        }
    }

    private func loadScorersIfNeeded() async {
        if !scorers.isEmpty { return }
        if let fetched = try? await NetworkHandler.getWorldCupScorers(), !fetched.isEmpty {
            scorers = fetched
        }
    }

    /// Non-empty standings groups (ESPN `children`), the World Cup's groups.
    var groups: [Child] {
        (standing?.standings.children ?? []).filter { ($0.standings?.entries?.isEmpty == false) }
    }

    var hasBracket: Bool {
        guard let bracket else { return false }
        return !bracket.isEmpty
    }
}
