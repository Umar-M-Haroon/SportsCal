@testable import App
import XCTVapor

/// Guards the rate-limit identity fix. The regression that bricked all writes was
/// keying on the shared `X-API-Key`, which collapsed every install into one
/// bucket. Identity must be per-device (`X-Install-ID`), falling back to IP.
final class RateLimitIdentityTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = Application(.testing)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    private func request(headers: HTTPHeaders) -> Request {
        Request(application: app, method: .POST, url: "/x", headers: headers, on: app.eventLoopGroup.next())
    }

    func testInstallIDTakesPrecedence() {
        var headers = HTTPHeaders()
        headers.add(name: "X-Install-ID", value: "device-123")
        headers.add(name: "X-API-Key", value: "shared-app-key")
        headers.add(name: "X-Forwarded-For", value: "9.9.9.9")
        XCTAssertEqual(RateLimitMiddleware.identity(for: request(headers: headers)), "id:device-123")
    }

    func testDistinctInstallsGetDistinctBuckets() {
        var a = HTTPHeaders()
        a.add(name: "X-API-Key", value: "shared-app-key")
        a.add(name: "X-Install-ID", value: "device-A")
        var b = HTTPHeaders()
        b.add(name: "X-API-Key", value: "shared-app-key")
        b.add(name: "X-Install-ID", value: "device-B")
        XCTAssertNotEqual(
            RateLimitMiddleware.identity(for: request(headers: a)),
            RateLimitMiddleware.identity(for: request(headers: b)),
            "Two installs sharing the app key must not share a bucket"
        )
    }

    func testFallsBackToFirstForwardedIP() {
        var headers = HTTPHeaders()
        headers.add(name: "X-Forwarded-For", value: "1.2.3.4, 5.6.7.8")
        XCTAssertEqual(RateLimitMiddleware.identity(for: request(headers: headers)), "ip:1.2.3.4")
    }

    func testSharedApiKeyAloneDoesNotDefineIdentity() {
        // No install-id, no forwarded IP: must NOT bucket on the shared API key
        // (which would re-introduce the global-bucket bug).
        var headers = HTTPHeaders()
        headers.add(name: "X-API-Key", value: "shared-app-key")
        let identity = RateLimitMiddleware.identity(for: request(headers: headers))
        XCTAssertFalse(identity.hasPrefix("k:"))
        XCTAssertTrue(identity.hasPrefix("ip:"))
    }
}
