import Foundation
import Vapor
import Queues
import Redis
import Logging

/// Keeps the `attest:key:*` keyspace honest: refreshes fraud-risk receipts that
/// have come due, and reaps records for installs that are plainly gone.
///
/// Two jobs in one because they walk the same keyspace, and that walk is the
/// expensive part — SCAN over every attested device, once an hour, is not
/// something to do twice.
///
/// Both halves are advisory. Receipt refresh feeds a metric nothing gates on
/// yet; reaping only removes records whose owner would silently re-attest on
/// next launch. Neither should ever be able to break a working install, so
/// every failure here is logged and swallowed.
struct AppAttestMaintenanceJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.appattest-maintenance")

    /// Ceiling on Apple round trips per tick. The walk is cheap; redeeming
    /// receipts is not, and a burst of thousands would be both slow and rude.
    /// Anything not reached this hour is reached the next — receipts stay
    /// redeemable for a long window, so there is no urgency.
    static let maxReceiptRefreshesPerRun = 200

    /// How long an unused key record survives. Deliberately generous: the cost
    /// of reaping too early is a forced re-attestation, which spends one of
    /// Apple's rate-limited `attestKey` calls for a user who did nothing wrong.
    /// Someone who opens the app twice a year keeps their key.
    static let unusedKeyRetention: TimeInterval = 180 * 24 * 3600

    // MARK: - Pure decisions

    /// Whether a stored receipt is due for redemption.
    ///
    /// Apple refuses a refresh before the receipt's not-before date with a 304,
    /// and the receipt is worthless after its expiry — so the window is
    /// `[notBefore, expiresAt)`. A record with no receipt has nothing to refresh.
    static func shouldRefreshReceipt(
        notBefore: Date?,
        expiresAt: Date?,
        hasReceipt: Bool,
        now: Date = Date()
    ) -> Bool {
        guard hasReceipt else { return false }
        if let notBefore, now < notBefore { return false }
        if let expiresAt, now >= expiresAt { return false }
        return true
    }

    /// Whether a key record belongs to an install we will never hear from again.
    ///
    /// `lastUsedAt` is written on every successful assertion refresh, so it is
    /// the real liveness signal. Records written before that field existed fall
    /// back to `createdAt`; a record with neither is treated as live rather than
    /// reaped, because deleting a key we cannot date is the one irreversible
    /// mistake available here.
    static func isAbandoned(
        lastUsedAt: Date?,
        createdAt: Date?,
        now: Date = Date(),
        retention: TimeInterval = unusedKeyRetention
    ) -> Bool {
        guard let reference = lastUsedAt ?? createdAt else { return false }
        return now.timeIntervalSince(reference) > retention
    }

    // MARK: - Run

    func run(context: QueueContext) async throws {
        let app = context.application
        // TTL comfortably exceeds a full walk; a crash mid-run leaves the lock
        // pinned only until the next hourly tick would have fired anyway.
        _ = try await JobLock.withLock(
            app.kv, name: "appattest-maintenance", ttl: 50 * 60,
            instanceID: app.instanceID, logger: Self.logger
        ) {
            await sweep(app: app)
        }
    }

    private func sweep(app: Application) async {
        let keys: [String]
        do {
            keys = try await app.kv.scanKeys(matching: "attest:key:*")
        } catch {
            Self.logger.warning("could not scan attest keyspace: \(error)")
            return
        }
        guard !keys.isEmpty else { return }

        let now = Date()
        var reaped = 0
        var refreshed = 0
        var attempted = 0

        for key in keys {
            let fields: [String: String]
            do {
                fields = try await app.redis.hgetall(from: RedisKey(key)).get()
                    .compactMapValues { $0.string }
            } catch {
                continue
            }

            if Self.isAbandoned(
                lastUsedAt: fields["lastUsedAt"].flatMap(Self.date),
                createdAt: fields["createdAt"].flatMap(Self.date),
                now: now
            ) {
                if (try? await app.redis.delete(RedisKey(key)).get()) != nil { reaped += 1 }
                continue
            }

            guard attempted < Self.maxReceiptRefreshesPerRun,
                  let deviceCheck = app.deviceCheck else { continue }
            guard Self.shouldRefreshReceipt(
                notBefore: fields["receiptNotBefore"].flatMap(Self.date),
                expiresAt: fields["receiptExpiresAt"].flatMap(Self.date),
                hasReceipt: fields["receipt"] != nil,
                now: now
            ) else { continue }

            attempted += 1
            if await refreshReceipt(key: key, fields: fields, deviceCheck: deviceCheck, app: app) {
                refreshed += 1
            }
        }

        Self.logger.info("App Attest maintenance", metadata: [
            "records": "\(keys.count)", "reaped": "\(reaped)",
            "receiptsRefreshed": "\(refreshed)", "receiptsAttempted": "\(attempted)",
        ])
    }

    private func refreshReceipt(
        key: String, fields: [String: String],
        deviceCheck: DeviceCheckClient, app: Application
    ) async -> Bool {
        guard let receiptB64 = fields["receipt"],
              let receipt = Data(base64Encoded: receiptB64) else { return false }
        // Environment is stored at attestation time: a receipt is only
        // redeemable against the host matching the client build that produced
        // it, and by now the attestation blob is long gone. Records written
        // before that field existed are overwhelmingly production.
        let environment = fields["environment"].flatMap(AppAttestEnvironment.init(rawValue:)) ?? .production

        do {
            guard let result = try await deviceCheck.fetchReceipt(
                receipt, environment: environment, on: app.client, logger: Self.logger
            ) else { return false }   // 304: asked too early, try next tick

            var updated: [String: String] = [
                "receipt": result.raw.base64EncodedString(),
                "receiptFetchedAt": "\(Int(Date().timeIntervalSince1970))",
                "environment": environment.rawValue,
            ]
            if let metric = result.parsed.riskMetric { updated["riskMetric"] = "\(metric)" }
            if let notBefore = result.parsed.notBefore {
                updated["receiptNotBefore"] = "\(Int(notBefore.timeIntervalSince1970))"
            }
            if let expires = result.parsed.expirationTime {
                updated["receiptExpiresAt"] = "\(Int(expires.timeIntervalSince1970))"
            }
            try await app.redis.hmset(updated, in: RedisKey(key)).get()
            await AppAttestRisk.record(
                metric: result.parsed.riskMetric, environment: environment, on: app
            )
            return true
        } catch {
            Self.logger.debug("receipt refresh failed for \(key.suffix(8)) (non-fatal): \(error)")
            return false
        }
    }

    private static func date(_ raw: String) -> Date? {
        guard let seconds = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
