import XCTest
@testable import SportsCalModel

final class SoccerMatchAnalyticsTests: XCTestCase {
    // MARK: Expected goals

    private func xG(metresOut: Double, metresWide: Double = 0,
                    bodyPart: SoccerShotBodyPart = .rightFoot,
                    situation: SoccerShotSituation = .openPlay) -> Double {
        SoccerExpectedGoals.estimate(
            x: 100 - metresOut / 105 * 100,
            y: 50 + metresWide / 68 * 100,
            bodyPart: bodyPart,
            situation: situation
        )
    }

    func testXGFallsWithDistance() {
        let close = xG(metresOut: 6)
        let spot = xG(metresOut: 11)
        let edge = xG(metresOut: 18)
        let long = xG(metresOut: 30)
        XCTAssertGreaterThan(close, spot)
        XCTAssertGreaterThan(spot, edge)
        XCTAssertGreaterThan(edge, long)
        // In line with published benchmarks for footed open-play shots.
        XCTAssertEqual(spot, 0.16, accuracy: 0.04)
        XCTAssertEqual(edge, 0.065, accuracy: 0.02)
    }

    func testXGFallsWithTighterAngle() {
        XCTAssertGreaterThan(xG(metresOut: 8), xG(metresOut: 8, metresWide: 12))
        // Symmetric left/right.
        XCTAssertEqual(xG(metresOut: 12, metresWide: 8), xG(metresOut: 12, metresWide: -8), accuracy: 1e-9)
    }

    func testXGAdjustments() {
        XCTAssertLessThan(xG(metresOut: 8, bodyPart: .head), xG(metresOut: 8))
        XCTAssertGreaterThan(xG(metresOut: 14, situation: .fastBreak), xG(metresOut: 14))
        XCTAssertEqual(xG(metresOut: 40, situation: .penalty), SoccerExpectedGoals.penalty)
    }

    // MARK: Shot narration

    func testReadsBodyPartAndSituationFromNarration() {
        let freeKick = "Attempt missed. Dominik Szoboszlai (Liverpool) right footed shot from outside the box is close, but misses the top left corner from a direct free kick."
        XCTAssertEqual(SoccerShotText.bodyPart(freeKick), .rightFoot)
        XCTAssertEqual(SoccerShotText.situation(freeKick, typeKey: "shot-off-target"), .directFreeKick)

        let header = "Attempt missed. Ryan Christie (Bournemouth) header from a difficult angle on the left is too high. Assisted by Adrien Truffert with a cross following a corner."
        XCTAssertEqual(SoccerShotText.bodyPart(header), .head)
        XCTAssertEqual(SoccerShotText.situation(header, typeKey: "shot-off-target"), .setPiece)

        let penalty = "Goal! Atletico Madrid 1, Real Madrid 0. Alejandro Grimaldo (Atletico Madrid) converts the penalty with a left footed shot to the bottom left corner."
        XCTAssertEqual(SoccerShotText.bodyPart(penalty), .leftFoot)
        XCTAssertEqual(SoccerShotText.situation(penalty, typeKey: "penalty---scored"), .penalty)
    }

    func testMapsPlayTypesToOutcomes() {
        XCTAssertEqual(SoccerShotText.outcome(typeKey: "shot-on-target", text: ""), .saved)
        XCTAssertEqual(SoccerShotText.outcome(typeKey: "shot-off-target", text: ""), .missed)
        XCTAssertEqual(SoccerShotText.outcome(typeKey: "shot-blocked", text: ""), .blocked)
        XCTAssertEqual(SoccerShotText.outcome(typeKey: "shot-hit-woodwork", text: ""), .woodwork)
        XCTAssertEqual(SoccerShotText.outcome(typeKey: "goal---header", text: ""), .goal)
        XCTAssertEqual(SoccerShotText.outcome(typeKey: "penalty---scored", text: ""), .goal)
        XCTAssertNil(SoccerShotText.outcome(typeKey: "own-goal", text: ""))
        XCTAssertNil(SoccerShotText.outcome(typeKey: "foul", text: ""))
    }

    // MARK: Momentum

    func testMomentumFollowsPressure() {
        var actions: [SoccerMomentum.Action] = []
        // Home pin the away side back for the first 20 minutes…
        for minute in stride(from: 1.0, through: 20, by: 2) {
            actions.append(.init(minute: minute, side: .home, x: 90, kind: .shot))
        }
        // …then the away side take over.
        for minute in stride(from: 60.0, through: 80, by: 2) {
            actions.append(.init(minute: minute, side: .away, x: 92, kind: .corner))
        }
        let series = SoccerMomentum.compute(actions, through: 90)
        XCTAssertEqual(series.count, 91)
        XCTAssertGreaterThan(series[10].value, 0.5)
        XCTAssertLessThan(series[70].value, -0.3)
        XCTAssertEqual(series[40].value, 0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(series.map { abs($0.value) }.max() ?? 0, 1)
    }

    func testMomentumIsEmptyWithoutActions() {
        XCTAssertTrue(SoccerMomentum.compute([]).isEmpty)
    }

    // MARK: Decoding older payloads

    func testDecodesPayloadWithoutNewerFields() throws {
        let json = """
        {"eventID":"760432","home":{"teamName":"France","players":[]},"away":{"teamName":"Senegal","players":[]},
         "teamStats":[],"events":[]}
        """
        let match = try JSONDecoder().decode(SoccerMatchDetail.self, from: Data(json.utf8))
        XCTAssertTrue(match.shots.isEmpty)
        XCTAssertTrue(match.home.form.isEmpty)
        XCTAssertNil(match.headToHead)
    }
}
