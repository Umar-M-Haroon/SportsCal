import Vapor
import Redis
import Queues
import QueuesRedisDriver
import VaporAPNS
import Crypto

struct APNSConfiguredKey: StorageKey {
    typealias Value = Bool
}

// configures your application
public func configure(_ app: Application) async throws {
    // Serve static files from /Public folder (for admin dashboard)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // register routes
    if let redisInfo = Environment.get("REDIS_HOST"), let redisPort = Environment.get("REDIS_PORT"), let redisPassword = Environment.get("REDIS_PASSWORD") {
        let redisConfig = try RedisConfiguration(hostname: redisInfo, port: Int(redisPort) ?? 6379, password: redisPassword)
        app.redis.configuration = redisConfig
        app.queues.use(.redis(redisConfig))
    } else {
        app.redis.configuration = try RedisConfiguration(hostname: "127.0.0.1")
        try app.queues.use(.redis(.init(hostname: "127.0.0.1", port: 6379)))
    }
    if let apnsKeyID = Environment.get("APNSkeyID"), let teamID = Environment.get("TeamID") {
        var keyPath = app.directory.workingDirectory
        keyPath.append("/AuthKey_\(apnsKeyID).p8")
        do {
            let keyData = try String(contentsOfFile: keyPath, encoding: .utf8)
            let key = try P256.Signing.PrivateKey.loadFrom(string: keyData)
            await app.apns.configure(
                .jwt(
                    privateKey: key,
                    keyIdentifier: apnsKeyID,
                    teamIdentifier: teamID
                )
            )
            app.storage[APNSConfiguredKey.self] = true
            app.logger.info("APNS configured successfully")
        } catch {
            app.logger.warning("⚠️ APNS not configured — AuthKey file not found at \(keyPath): \(error)")
        }
    } else {
        app.logger.warning("⚠️ APNS not configured — APNSkeyID or TeamID environment variables missing")
    }
        
    // Warn if TheSportsDB API key is not configured
    if Environment.get("SportsDB_API_KEY") == nil {
        app.logger.warning("⚠️ SportsDB_API_KEY not set — TheSportsDB v2 API calls will fail (400)")
    }

    // Open the SQLite play-by-play archive. Path override via PBP_ARCHIVE_PATH env var —
    // defaults to `pbp_archive.sqlite` alongside the other working-directory artifacts.
    do {
        let defaultPath = app.directory.workingDirectory + "pbp_archive.sqlite"
        let archivePath = Environment.get("PBP_ARCHIVE_PATH") ?? defaultPath
        app.pbpArchive = try await PBPArchive.bootstrap(path: archivePath)
        app.logger.info("📦 PBP archive opened at \(archivePath)")
    } catch {
        app.logger.error("⚠️ PBP archive failed to open — historical plays won't persist: \(error)")
    }

    // Skip scheduled jobs during testing to avoid external API calls
    if app.environment != .testing {
        let scheduleUpdateJob = ScheduleUpdateJob()
        app.queues.schedule(scheduleUpdateJob)
            .minutely()
            .at(30)
        let espnSoccerJob = ESPNSoccerJob()
        app.queues.schedule(espnSoccerJob)
            .minutely()
            .at(7)
        let espnTennisJob = ESPNTennisJob()
        app.queues.schedule(espnTennisJob)
            .minutely()
            .at(2)
        let ESPNJob = ESPNFetchJob()
        app.queues.schedule(ESPNJob)
            .minutely()
            .at(15)
        let teamJob = ESPNTeamFetchJob()
        app.queues.schedule(teamJob)
            .hourly()
            .at(38)
        let apnsJob = APNSJob()
        app.queues.schedule(apnsJob)
            .minutely()
            .at(5)
        // DISABLED: Standings history snapshots
//        let standingsSnapshotJob = StandingsSnapshotJob()
//        app.queues.schedule(standingsSnapshotJob)
//            .daily()
//            .at(.init(integerLiteral: 6), .init(integerLiteral: 0))
        let f1EnrichmentJob = F1EnrichmentJob()
        app.queues.schedule(f1EnrichmentJob)
            .hourly()
            .at(10)
        let golfEnrichmentJob = GolfEnrichmentJob()
        app.queues.schedule(golfEnrichmentJob)
            .hourly()
            .at(25)
        let injuriesEnrichmentJob = InjuriesEnrichmentJob()
        app.queues.schedule(injuriesEnrichmentJob)
            .hourly()
            .at(42)

        try app.queues.startScheduledJobs()
    }
    // Bind to all interfaces so Tailscale and LAN clients can reach the server
    app.http.server.configuration.hostname = "0.0.0.0"

    try routes(app)

    // Start interactive log commands reader (stdin)
    startLogCommands()

    // Advertise via Bonjour so the iOS app can discover the local dev server
    #if os(macOS)
    if app.environment == .development {
        let port = app.http.server.configuration.port
        let service = NetService(domain: "", type: "_sportscal._tcp.", name: "SportsCal Dev", port: Int32(port))
        service.publish()
        app.storage[BonjourServiceKey.self] = service
        app.logger.info("📡 Bonjour: advertising _sportscal._tcp on port \(port)")
    }
    #endif
}

#if os(macOS)
private struct BonjourServiceKey: StorageKey {
    typealias Value = NetService
}
#endif
