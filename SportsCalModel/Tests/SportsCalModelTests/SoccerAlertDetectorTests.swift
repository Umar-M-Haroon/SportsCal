import XCTest
@testable import SportsCalModel

final class SoccerAlertDetectorTests: XCTestCase {
    private func xi(_ team: String) -> [SoccerLineupPlayer] {
        (1...11).map { SoccerLineupPlayer(name: "\(team) \($0)", starter: true, formationPlace: $0) }
    }

    private func match(
        state: String = "in", name: String? = "STATUS_FIRST_HALF", home: Int? = 0, away: Int? = 0,
        lineups: Bool = true, events: [SoccerMatchEvent] = [], commentary: [SoccerCommentaryEntry] = []
    ) -> SoccerMatchDetail {
        SoccerMatchDetail(
            eventID: "401879276",
            home: SoccerLineup(teamName: "Bournemouth", formation: "4-2-3-1", players: lineups ? xi("BOU") : []),
            away: SoccerLineup(teamName: "Liverpool", formation: "4-3-3", players: lineups ? xi("LIV") : []),
            events: events,
            commentary: commentary,
            status: SoccerMatchStatus(state: state, name: name, homeScore: home, awayScore: away)
        )
    }

    private let isakGoal = SoccerMatchEvent(
        id: "e57", type: .goal, typeText: "Goal", clock: "57'", period: 2, side: .away,
        scoringPlay: true, playerNames: ["Alexander Isak", "Florian Wirtz"]
    )

    // MARK: First look

    func testFirstLookTakesTheMatchAsSeen() {
        let (alerts, state) = SoccerAlertDetector.detect(
            match(state: "in", name: "STATUS_SECOND_HALF", home: 0, away: 1, events: [isakGoal]),
            previous: nil
        )
        XCTAssertTrue(alerts.isEmpty, "no burst of stale alerts when the job first sees a match")
        XCTAssertTrue(state.seenIDs.contains("e57"))
        XCTAssertTrue(state.halfTimeAnnounced)
        XCTAssertFalse(state.fullTimeAnnounced)
    }

    func testFirstLookBeforeKickoffAnnouncesLineups() {
        let (alerts, state) = SoccerAlertDetector.detect(match(state: "pre", name: "STATUS_SCHEDULED", home: nil, away: nil), previous: nil)
        XCTAssertEqual(alerts.map(\.kind), [.lineups])
        XCTAssertEqual(alerts.first?.body, "Bournemouth v Liverpool · 4-2-3-1 v 4-3-3. Tap to see the starting XIs.")
        XCTAssertTrue(state.lineupsAnnounced)
    }

    // MARK: Lineups

    func testLineupsAnnouncedOnceWhenTheyAppear() {
        let (_, before) = SoccerAlertDetector.detect(match(state: "pre", lineups: false), previous: nil)
        XCTAssertFalse(before.lineupsAnnounced)
        let (alerts, after) = SoccerAlertDetector.detect(match(state: "pre"), previous: before)
        XCTAssertEqual(alerts.map(\.kind), [.lineups])
        let (again, _) = SoccerAlertDetector.detect(match(state: "pre"), previous: after)
        XCTAssertTrue(again.isEmpty)
    }

    // MARK: In-play events

    func testNewGoalIsAnnouncedWithScoreAndScorer() {
        let (_, kickoff) = SoccerAlertDetector.detect(match(), previous: nil)
        let (alerts, state) = SoccerAlertDetector.detect(match(home: 0, away: 1, events: [isakGoal]), previous: kickoff)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.kind, .goal)
        XCTAssertEqual(alerts.first?.title, "⚽️ Goal! Bournemouth 0–1 Liverpool")
        XCTAssertEqual(alerts.first?.body, "Alexander Isak 57', assist Florian Wirtz")
        XCTAssertEqual(alerts.first?.id, "401879276-e57")
        // Seen now: the next look is quiet.
        XCTAssertTrue(SoccerAlertDetector.detect(match(home: 0, away: 1, events: [isakGoal]), previous: state).alerts.isEmpty)
    }

    func testRedCardAndMissedPenaltyButNotYellowsOrSubs() {
        let (_, kickoff) = SoccerAlertDetector.detect(match(), previous: nil)
        let events = [
            SoccerMatchEvent(id: "y", type: .yellowCard, typeText: "Yellow Card", clock: "20'", side: .home, playerNames: ["Scott"]),
            SoccerMatchEvent(id: "r", type: .redCard, typeText: "Red Card", clock: "51'", side: .home, playerNames: ["Senesi"]),
            SoccerMatchEvent(id: "p", type: .penaltyMissed, typeText: "Penalty - Saved", clock: "70'", side: .away, playerNames: ["Salah"]),
            SoccerMatchEvent(id: "s", type: .substitution, typeText: "Substitution", clock: "60'", side: .away),
        ]
        let alerts = SoccerAlertDetector.detect(match(events: events), previous: kickoff).alerts
        XCTAssertEqual(alerts.map(\.kind), [.redCard, .penaltyMissed])
        XCTAssertEqual(alerts.first?.title, "🟥 Red card — Bournemouth")
        XCTAssertEqual(alerts.first?.body, "Senesi is sent off 51'. Bournemouth 0–0 Liverpool")
    }

    func testVARReversalAnnouncedOnceForItsPairOfLines() {
        let (_, kickoff) = SoccerAlertDetector.detect(match(), previous: nil)
        let commentary = [
            SoccerCommentaryEntry(id: "1", clock: "55'", text: "GOAL OVERTURNED BY VAR: Kees Smit (AZ) scores but the goal is ruled out after a VAR review.", kind: .var, side: .home),
            SoccerCommentaryEntry(id: "2", clock: "57'", text: "VAR Decision: No Goal AZ 1-0 Telstar.", kind: .var, side: .home),
            SoccerCommentaryEntry(id: "3", clock: "60'", text: "VAR Decision: Card upgraded Smit (AZ).", kind: .var, side: .home),
        ]
        let alerts = SoccerAlertDetector.detect(match(commentary: commentary), previous: kickoff).alerts
        XCTAssertEqual(alerts.map(\.kind), [.goalDisallowed])
        XCTAssertTrue(alerts.first?.body.hasPrefix("55' GOAL OVERTURNED") ?? false)
    }

    // MARK: Period boundaries

    func testHalfTimeThenFullTimeOnceEach() {
        let (_, kickoff) = SoccerAlertDetector.detect(match(), previous: nil)
        let (ht, s1) = SoccerAlertDetector.detect(match(name: "STATUS_HALFTIME", home: 1, away: 0), previous: kickoff)
        XCTAssertEqual(ht.map(\.kind), [.halfTime])
        XCTAssertEqual(ht.first?.body, "Bournemouth 1–0 Liverpool")
        let (quiet, s2) = SoccerAlertDetector.detect(match(name: "STATUS_HALFTIME", home: 1, away: 0), previous: s1)
        XCTAssertTrue(quiet.isEmpty)
        let (ft, s3) = SoccerAlertDetector.detect(match(state: "post", name: "STATUS_FULL_TIME", home: 1, away: 2), previous: s2)
        XCTAssertEqual(ft.map(\.kind), [.fullTime])
        XCTAssertEqual(ft.first?.body, "Bournemouth 1–2 Liverpool")
        XCTAssertTrue(SoccerAlertDetector.detect(match(state: "post", name: "STATUS_FULL_TIME", home: 1, away: 2), previous: s3).alerts.isEmpty)
    }

    func testFullTimeWithoutAHalfTimeLookStillAnnouncesOnlyFullTime() {
        let (_, kickoff) = SoccerAlertDetector.detect(match(), previous: nil)
        let alerts = SoccerAlertDetector.detect(match(state: "post", name: "STATUS_FULL_TIME", home: 2, away: 2), previous: kickoff).alerts
        XCTAssertEqual(alerts.map(\.kind), [.fullTime])
    }
}
