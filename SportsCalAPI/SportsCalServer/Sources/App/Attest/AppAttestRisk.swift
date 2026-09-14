import Foundation
import Vapor

/// Turns App Attest's fraud-risk metric into something a threshold can later be
/// chosen from.
///
/// The metric is the number of attested keys a device minted in the last 30
/// days — high counts suggest one jailbroken device farming keys for many
/// clients. Apple's guidance is to observe real traffic before enforcing
/// anything, and that is exactly what has been missing: the metric was being
/// stored per key and logged, which answers "what is this device's count" but
/// never "what is normal". Without a distribution, any threshold would be a
/// guess, and a wrong guess locks real users out of the app.
///
/// So this deliberately stops at observation. It emits a bucketed counter into
/// the same per-day Redis counters the admin dashboard already reads, and
/// enforcement stays unimplemented until those numbers say what normal is.
enum AppAttestRisk {

    /// Buckets rather than raw values: a counter per distinct metric would grow
    /// an unbounded keyspace and produce a histogram nobody can read. These
    /// edges are chosen to make the interesting tail visible — almost every
    /// honest device sits at 1–2, so the resolution belongs above that.
    static func bucket(_ metric: Int) -> String {
        switch metric {
        case ..<1:    return "0"
        case 1:       return "1"
        case 2:       return "2"
        case 3...5:   return "3-5"
        case 6...10:  return "6-10"
        case 11...25: return "11-25"
        default:      return "26+"
        }
    }

    /// Records one observation. Fire-and-forget; a telemetry failure must never
    /// affect attestation.
    static func record(
        metric: Int?,
        environment: AppAttestEnvironment,
        on app: Application
    ) async {
        guard let metric else { return }
        await app.telemetry.info("attest.risk_metric", [
            "bucket": bucket(metric),
            "environment": environment.rawValue,
        ])
    }
}
