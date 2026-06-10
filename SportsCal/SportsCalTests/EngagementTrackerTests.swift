import XCTest
import SportsCalModel
@testable import Scoreline

/// Pins the EngagementTracker suggestion threshold, favorites exclusion, and
/// the D3 "Reset Suggestions" behavior — including that reset clears the
/// persisted copy, not just the in-memory dictionary.
final class EngagementTrackerTests: XCTestCase {

    override func setUp() {
        EngagementTracker().reset()
    }

    override func tearDown() {
        EngagementTracker().reset()
    }

    func testRepeatedViewsCrossSuggestionThreshold() {
        // 5 views, not 4: the decayed score of 4 same-instant views is
        // fractionally below the 4.0 threshold (microseconds of decay).
        let tracker = EngagementTracker()
        for _ in 1...5 {
            tracker.recordView(team: "Lakers", sport: .basketball)
        }

        XCTAssertTrue(tracker.suggestedTeamNames(excluding: []).contains("Lakers"))
        XCTAssertEqual(tracker.topSuggestedTeam(excluding: [])?.teamName, "Lakers")
    }

    func testFewViewsDoNotSuggest() {
        let tracker = EngagementTracker()
        tracker.recordView(team: "Lakers", sport: .basketball)

        XCTAssertFalse(tracker.suggestedTeamNames(excluding: []).contains("Lakers"))
    }

    func testFavoritesAreExcludedFromSuggestions() {
        let tracker = EngagementTracker()
        for _ in 1...5 {
            tracker.recordView(team: "Lakers", sport: .basketball)
        }

        XCTAssertFalse(tracker.suggestedTeamNames(excluding: ["Lakers"]).contains("Lakers"))
        XCTAssertNil(tracker.topSuggestedTeam(excluding: ["Lakers"]))
    }

    func testResetClearsInMemoryAndPersistedState() {
        let tracker = EngagementTracker()
        for _ in 1...4 {
            tracker.recordView(team: "Lakers", sport: .basketball)
        }
        XCTAssertFalse(tracker.engagements.isEmpty)

        tracker.reset()

        XCTAssertTrue(tracker.engagements.isEmpty)
        // A fresh tracker re-reads from defaults — must come up empty too,
        // or the suggestions would resurrect on next launch.
        let reloaded = EngagementTracker()
        XCTAssertTrue(reloaded.engagements.isEmpty)
    }
}
