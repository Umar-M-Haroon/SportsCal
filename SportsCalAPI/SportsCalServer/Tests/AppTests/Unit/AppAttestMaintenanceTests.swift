@testable import App
import XCTest

/// Pins the two decisions `AppAttestMaintenanceJob` makes about a key record.
///
/// Both are one-way in the direction that hurts: refreshing a receipt outside
/// its window wastes an Apple round trip, and reaping a live record forces a
/// user who did nothing wrong to spend one of Apple's rate-limited `attestKey`
/// calls. So the tests lean on the boundaries and on the "when in doubt, do
/// nothing" cases.
final class AppAttestMaintenanceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private func offset(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    // MARK: - Receipt refresh window

    func testRefreshesInsideTheWindow() {
        XCTAssertTrue(AppAttestMaintenanceJob.shouldRefreshReceipt(
            notBefore: offset(-3600), expiresAt: offset(3600), hasReceipt: true, now: now))
    }

    /// Apple answers 304 before the not-before date — a wasted round trip.
    func testDoesNotRefreshBeforeNotBefore() {
        XCTAssertFalse(AppAttestMaintenanceJob.shouldRefreshReceipt(
            notBefore: offset(60), expiresAt: offset(3600), hasReceipt: true, now: now))
    }

    func testRefreshesExactlyAtNotBefore() {
        XCTAssertTrue(AppAttestMaintenanceJob.shouldRefreshReceipt(
            notBefore: now, expiresAt: offset(3600), hasReceipt: true, now: now))
    }

    /// An expired receipt is not redeemable; retrying it forever would burn a
    /// slot every tick and never succeed.
    func testDoesNotRefreshAfterExpiry() {
        XCTAssertFalse(AppAttestMaintenanceJob.shouldRefreshReceipt(
            notBefore: offset(-7200), expiresAt: offset(-1), hasReceipt: true, now: now))
    }

    func testDoesNotRefreshExactlyAtExpiry() {
        XCTAssertFalse(AppAttestMaintenanceJob.shouldRefreshReceipt(
            notBefore: offset(-7200), expiresAt: now, hasReceipt: true, now: now))
    }

    func testDoesNotRefreshWithoutAReceipt() {
        XCTAssertFalse(AppAttestMaintenanceJob.shouldRefreshReceipt(
            notBefore: offset(-3600), expiresAt: offset(3600), hasReceipt: false, now: now))
    }

    /// Records written before the date fields existed still carry a receipt;
    /// missing bounds must not block them forever.
    func testRefreshesWhenBoundsAreUnknown() {
        XCTAssertTrue(AppAttestMaintenanceJob.shouldRefreshReceipt(
            notBefore: nil, expiresAt: nil, hasReceipt: true, now: now))
    }

    // MARK: - Reaping

    func testReapsLongUnusedRecord() {
        XCTAssertTrue(AppAttestMaintenanceJob.isAbandoned(
            lastUsedAt: offset(-200 * 24 * 3600), createdAt: offset(-400 * 24 * 3600), now: now))
    }

    func testKeepsRecentlyUsedRecord() {
        XCTAssertFalse(AppAttestMaintenanceJob.isAbandoned(
            lastUsedAt: offset(-24 * 3600), createdAt: offset(-400 * 24 * 3600), now: now),
            "an old key still in daily use must never be reaped")
    }

    /// `lastUsedAt` is the real signal; `createdAt` only fills in for records
    /// written before that field existed.
    func testLastUsedWinsOverCreatedAt() {
        XCTAssertFalse(AppAttestMaintenanceJob.isAbandoned(
            lastUsedAt: now, createdAt: offset(-1000 * 24 * 3600), now: now))
    }

    func testFallsBackToCreatedAtWhenNeverUsed() {
        XCTAssertTrue(AppAttestMaintenanceJob.isAbandoned(
            lastUsedAt: nil, createdAt: offset(-200 * 24 * 3600), now: now))
        XCTAssertFalse(AppAttestMaintenanceJob.isAbandoned(
            lastUsedAt: nil, createdAt: offset(-10 * 24 * 3600), now: now))
    }

    /// The one irreversible mistake available here is deleting a key we cannot
    /// date, so an undateable record is kept.
    func testKeepsRecordWithNoDatesAtAll() {
        XCTAssertFalse(AppAttestMaintenanceJob.isAbandoned(
            lastUsedAt: nil, createdAt: nil, now: now),
            "a record with no dates must be kept, not reaped")
    }

    func testRetentionBoundaryIsNotInclusive() {
        let retention = AppAttestMaintenanceJob.unusedKeyRetention
        XCTAssertFalse(AppAttestMaintenanceJob.isAbandoned(
            lastUsedAt: offset(-retention), createdAt: nil, now: now))
        XCTAssertTrue(AppAttestMaintenanceJob.isAbandoned(
            lastUsedAt: offset(-retention - 1), createdAt: nil, now: now))
    }

    /// Six months is a deliberate choice, not an accident of units — a shorter
    /// window would re-attest seasonal users for nothing.
    func testRetentionIsGenerous() {
        XCTAssertGreaterThanOrEqual(AppAttestMaintenanceJob.unusedKeyRetention, 90 * 24 * 3600)
    }

    // MARK: - Risk-metric bucketing

    func testBucketsCoverTheCommonCase() {
        // Honest devices sit at 1-2; these must be distinguishable or the
        // distribution says nothing about where normal ends.
        XCTAssertEqual(AppAttestRisk.bucket(1), "1")
        XCTAssertEqual(AppAttestRisk.bucket(2), "2")
    }

    func testBucketsCompressTheTail() {
        XCTAssertEqual(AppAttestRisk.bucket(3), "3-5")
        XCTAssertEqual(AppAttestRisk.bucket(5), "3-5")
        XCTAssertEqual(AppAttestRisk.bucket(6), "6-10")
        XCTAssertEqual(AppAttestRisk.bucket(10), "6-10")
        XCTAssertEqual(AppAttestRisk.bucket(11), "11-25")
        XCTAssertEqual(AppAttestRisk.bucket(25), "11-25")
    }

    /// The keyspace must stay bounded no matter what Apple reports.
    func testExtremeValuesCollapseIntoOneBucket() {
        XCTAssertEqual(AppAttestRisk.bucket(26), "26+")
        XCTAssertEqual(AppAttestRisk.bucket(10_000), "26+")
        XCTAssertEqual(AppAttestRisk.bucket(Int.max), "26+")
    }

    func testNonPositiveValuesAreHandled() {
        XCTAssertEqual(AppAttestRisk.bucket(0), "0")
        XCTAssertEqual(AppAttestRisk.bucket(-1), "0")
    }
}
