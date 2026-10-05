@testable import App
import XCTVapor
import SportsCalModel
import Foundation

/// Replays consecutive `/schedules` bodies captured from production and reports how
/// often the old content-hash ETag and the calendar ETag would have changed.
/// Opt-in: set SCHEDULE_SNAPSHOTS to a directory of `NN.json` files (in capture order).
final class ScheduleChurnReplayTests: XCTestCase {
    func testCalendarVersionIgnoresLiveTicks() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCHEDULE_SNAPSHOTS"] else {
            throw XCTSkip("set SCHEDULE_SNAPSHOTS to a directory of captured /schedules bodies")
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".json") }.sorted()
        XCTAssertGreaterThan(files.count, 1)
        var contentChanges = 0, calendarChanges = 0
        var previous: (content: String, calendar: [String: String])?
        for file in files {
            let data = try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(file))
            let schedule = try JSONDecoder().decode(LiveScore.self, from: data)
            let content = PayloadVersion.of(String(decoding: data, as: UTF8.self))
            let calendar = ScheduleCalendarVersion.versions(of: schedule)
            if let previous {
                if previous.content != content { contentChanges += 1 }
                if previous.calendar != calendar {
                    calendarChanges += 1
                    let moved = calendar.keys.filter { previous.calendar[$0] != calendar[$0] }.sorted()
                    print("CHURN \(file): calendar changed in \(moved)")
                } else {
                    print("CHURN \(file): content changed, calendar unchanged")
                }
            }
            previous = (content, calendar)
        }
        print("CHURN over \(files.count) snapshots: content ETag changed \(contentChanges)x, calendar ETag changed \(calendarChanges)x")
        XCTAssertLessThan(calendarChanges, contentChanges)
    }

    /// Slice sizes after golf slimming, and that the slices add back up to the schedule.
    func testSlicesOfARealSchedule() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCHEDULE_SNAPSHOTS"] else {
            throw XCTSkip("set SCHEDULE_SNAPSHOTS to a directory of captured /schedules bodies")
        }
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".json") }.sorted().last)
        let original = try JSONDecoder().decode(LiveScore.self, from: Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(file)))
        let slimmed = ScheduleSlimming.slimmed(original)
        let json = String(decoding: try JSONEncoder().encode(slimmed), as: UTF8.self)
        let before = try JSONEncoder().encode(original).count
        print("SLICE schedule \(before / 1000)KB -> \(json.utf8.count / 1000)KB after golf slimming")
        var parts: [LiveScore] = []
        for key in LiveScore.WireKey.allCases {
            let body = ScheduleSlice.body(for: key, in: json)
            print("SLICE \(key.rawValue): \(body.utf8.count / 1000)KB")
            parts.append(try JSONDecoder().decode(LiveScore.self, from: Data(body.utf8)))
        }
        let combined = LiveScore.combining(parts)
        for (sport, games) in slimmed.allGamesBySport {
            XCTAssertEqual(combined.event(for: sport)?.events.count, games.count, "\(sport)")
        }
    }
}
