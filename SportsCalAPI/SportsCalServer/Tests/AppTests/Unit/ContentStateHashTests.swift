import XCTest
@testable import App

/// Pins ContentState.stableHash() — the Live Activity dedup key component in
/// `EventStateClaim-{eventID}-{stateHash}`. The hash must be identical across
/// processes AND across deploys: if the encoding ever changes, every in-flight
/// claim key misses during a rolling restart and devices receive duplicate
/// Live Activity pushes for states that were already delivered.
final class ContentStateHashTests: XCTestCase {

    private let fullState = ContentState(
        homeScore: 12, awayScore: 9,
        status: "in", progress: "4:20 - 1st", lastPlay: "Jumper made"
    )

    func testGoldenHashFullyPopulated() {
        // Hard-coded pin. DO NOT update this value casually — a change here
        // means the wire encoding changed and cross-deploy dedup will break
        // (duplicate pushes during rolling restarts). sortedKeys JSON:
        // {"awayScore":9,"homeScore":12,"lastPlay":"Jumper made","progress":"4:20 - 1st","status":"in"}
        XCTAssertEqual(
            fullState.stableHash(),
            "88ddcb80aafdf29d37957df49d78500f57d8ac2ca97b5ef0b76b82fe41f06dc4"
        )
    }

    func testGoldenHashMinimalState() {
        // Pins that nil optionals are OMITTED (encodeIfPresent), not encoded
        // as null. sortedKeys JSON: {"awayScore":9,"homeScore":12}
        let minimal = ContentState(homeScore: 12, awayScore: 9, status: nil, progress: nil, lastPlay: nil)
        XCTAssertEqual(
            minimal.stableHash(),
            "6aeb2136773f135f48aee7ce8beb1167a7b4a0deda3d43a7ca6a99316f398624"
        )
    }

    func testEqualStatesProduceEqualHashes_andRepeatedCallsAreStable() {
        let copy = ContentState(
            homeScore: 12, awayScore: 9,
            status: "in", progress: "4:20 - 1st", lastPlay: "Jumper made"
        )
        XCTAssertEqual(fullState.stableHash(), copy.stableHash())
        XCTAssertEqual(fullState.stableHash(), fullState.stableHash())
    }

    func testEveryFieldMutationChangesHash() {
        let base = fullState.stableHash()

        var mutated = fullState
        mutated.homeScore = 13
        XCTAssertNotEqual(mutated.stableHash(), base)

        mutated = fullState
        mutated.awayScore = 10
        XCTAssertNotEqual(mutated.stableHash(), base)

        mutated = fullState
        mutated.status = "post"
        XCTAssertNotEqual(mutated.stableHash(), base)

        mutated = fullState
        mutated.progress = "4:19 - 1st"
        XCTAssertNotEqual(mutated.stableHash(), base)

        mutated = fullState
        mutated.lastPlay = "Free throw"
        XCTAssertNotEqual(mutated.stableHash(), base)
    }

    func testNilToNonNilTransitionsChangeHash() {
        let withNils = ContentState(homeScore: 12, awayScore: 9, status: nil, progress: nil, lastPlay: nil)
        var withStatus = withNils
        withStatus.status = "in"
        XCTAssertNotEqual(withStatus.stableHash(), withNils.stableHash())
    }

    func testHashFormatIs64LowercaseHexChars() {
        let hash = fullState.stableHash()
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
