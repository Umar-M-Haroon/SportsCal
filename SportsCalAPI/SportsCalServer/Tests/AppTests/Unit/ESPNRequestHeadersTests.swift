@testable import App
import XCTVapor
import XCTest

/// Guards the two mitigations for ESPN's Akamai bot filter (which began 403-ing us in
/// August 2026, freezing every ESPN-sourced feed behind stale cache).
final class ESPNRequestHeadersTests: XCTestCase {

    /// Akamai 403s requests whose User-Agent it doesn't recognise as a known HTTP client.
    /// Our own product tokens ("SportsCal/3.2") are rejected; library tokens pass.
    func testUserAgentIsARecognisedClientToken() {
        let ua = ESPNNetworking.userAgent
        XCTAssertFalse(ua.isEmpty, "an empty User-Agent is exactly what Akamai blocks")
        let recognised = ["AsyncHTTPClient/", "curl/", "okhttp/"]
        XCTAssertTrue(
            recognised.contains { ua.hasPrefix($0) },
            "\(ua) is not a client token Akamai is known to allow"
        )
    }

    func testWebAPIFallbackRewritesOnlySiteAPIHost() {
        let primary = URI(string: "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard?limit=500")
        let fallback = ESPNNetworking.webAPIFallback(for: primary)
        XCTAssertEqual(fallback?.host, "site.web.api.espn.com")
        XCTAssertEqual(fallback?.path, primary.path, "path must survive the host swap")
        XCTAssertEqual(fallback?.query, primary.query, "query must survive the host swap")
    }

    func testWebAPIFallbackIgnoresOtherESPNHosts() {
        // sports.core.api has no site.web mirror — rewriting it would 404.
        let core = URI(string: "https://sports.core.api.espn.com/v2/sports/racing/leagues/f1/events/1")
        XCTAssertNil(ESPNNetworking.webAPIFallback(for: core))
    }
}
