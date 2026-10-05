//
//  AlKamelService.swift
//
//  IMSA and WEC race weekends: TheSportsDB for the schedule, Al Kamel's public results
//  files for every session's classification (see AlKamelFeed.swift). An event's parsed
//  sessions are cached for good once its race is final; until then for five minutes,
//  which is also how "live" an endurance race gets (results are published hourly).
//

import Foundation
import Vapor
import SportsCalModel

enum AlKamelSeries: String, CaseIterable, Codable {
    case imsa, wec

    var league: Leagues { self == .imsa ? .imsa : .wec }

    var base: String {
        switch self {
        case .imsa: "https://imsa.results.alkamelcloud.com/"
        case .wec: "https://fiawec.alkamelsystems.com/"
        }
    }

    /// The championship folder for the series itself (events also host support series).
    func isChampionship(_ folder: String) -> Bool {
        let name = folder.split(separator: "_", maxSplits: 1).last.map(String.init) ?? folder
        switch self {
        case .imsa: return name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("IMSA WeatherTech SportsCar Championship") == .orderedSame
        case .wec: return name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("FIA WEC") == .orderedSame
        }
    }

    /// Local track time when TheSportsDB doesn't give a usable race time to derive it from.
    var fallbackTimeZone: TimeZone { self == .imsa ? TimeZone(identifier: "America/New_York")! : TimeZone(identifier: "UTC")! }
}

enum AlKamelService {
    private static let logger = Logger(label: "com.sportscal.alkamel")

    // MARK: - Cache keys

    private static func key(_ name: String, isDebug: Bool) -> String { (isDebug ? "debug-" : "") + name }
    static func eventKey(_ series: AlKamelSeries, path: String, isDebug: Bool) -> String { key("AlKamel \(series.rawValue) \(path)", isDebug: isDebug) }
    static func weekendsKey(_ series: AlKamelSeries, isDebug: Bool) -> String { key("AlKamel \(series.rawValue) Weekends", isDebug: isDebug) }
    static func standingsKey(_ series: AlKamelSeries, isDebug: Bool) -> String { key("AlKamel \(series.rawValue) Standings", isDebug: isDebug) }

    /// A weekend as cached for the live path and race detail.
    struct CachedWeekend: Codable {
        let weekend: IndyCarService.CachedWeekend
        /// "Results/26_2026/21_Road Atlanta" — the Al Kamel event, when matched.
        let eventPath: String?
    }

    // MARK: - HTTP

    private static func get(_ url: String, client: some Client) async throws -> ClientResponse {
        let response = try await client.get(URI(string: url)) { req in
            req.headers.replaceOrAdd(name: .userAgent, value: ESPNNetworking.userAgent)
        }
        guard response.status == .ok else { throw Abort(.badGateway, reason: "\(url): \(response.status.code)") }
        return response
    }

    private static func text(_ response: ClientResponse) -> String {
        response.body.map { String(buffer: $0) } ?? ""
    }

    private static func data(_ response: ClientResponse) -> Data {
        response.body.map { Data(buffer: $0) } ?? Data()
    }

    /// The URL of a site-relative path, percent-encoding spaces and the like.
    static func url(_ series: AlKamelSeries, _ path: String) -> String {
        let decoded = path.removingPercentEncoding ?? path
        let encoded = decoded.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? decoded
        return series.base + (encoded.hasPrefix("/") ? String(encoded.dropFirst()) : encoded)
    }

    /// Subfolders and files of an IMSA directory listing, as full site paths.
    private static func imsaListing(_ path: String, client: some Client) async throws -> [String] {
        let html = text(try await get(url(.imsa, path + "/"), client: client))
        return AlKamelParse.links(in: html)
            .filter { !$0.hasPrefix("/") && !$0.hasPrefix("http") }
            .map { path + "/" + ($0.removingPercentEncoding ?? $0).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    }

    /// Every result file of a WEC event. The site's folders aren't listable; the page for
    /// an event links them all. POST, not GET: the CDN ignores the query string when
    /// caching, so a GET returns whichever event was cached last.
    private static func wecEventPage(season: String, event: String, client: some Client) async throws -> String {
        let response = try await client.post(URI(string: AlKamelSeries.wec.base)) { req in
            req.headers.replaceOrAdd(name: .userAgent, value: ESPNNetworking.userAgent)
            try req.content.encode(["season": season, "evvent": event], as: .urlEncodedForm)
        }
        guard response.status == .ok else { throw Abort(.badGateway, reason: "WEC \(event): \(response.status.code)") }
        return text(response)
    }

    // MARK: - Seasons and events

    /// The season folder ("26_2026", "15_2026") for `year`.
    static func seasonFolder(_ series: AlKamelSeries, year: Int, client: some Client) async throws -> String? {
        switch series {
        case .imsa:
            return try await imsaListing("Results", client: client)
                .map { $0.replacingOccurrences(of: "Results/", with: "") }
                .first { $0.hasSuffix("_\(year)") }
        case .wec:
            let html = text(try await get(series.base, client: client))
            return AlKamelParse.options(named: "season", in: html).first { $0.hasSuffix("_\(year)") }
        }
    }

    /// Event folders of a season ("21_Road Atlanta", "06_FUJI SPEEDWAY").
    static func events(_ series: AlKamelSeries, season: String, client: some Client) async throws -> [String] {
        switch series {
        case .imsa:
            return try await imsaListing("Results/\(season)", client: client).map { ($0 as NSString).lastPathComponent }
        case .wec:
            let html = try await wecEventPage(season: season, event: "", client: client)
            return AlKamelParse.options(named: "evvent", in: html)
        }
    }

    // MARK: - An event's sessions

    /// The event's sessions with results, cached (final: for good; otherwise 5 minutes).
    static func sessions(_ series: AlKamelSeries, season: String, event: String, app: Application, isDebug: Bool) async -> [AlKamelSession] {
        let path = "Results/\(season)/\(event)"
        let cacheKey = eventKey(series, path: path, isDebug: isDebug)
        if let cached = try? await app.kv.getJSON(cacheKey, as: [AlKamelSession].self) { return cached }
        do {
            var sessions = try await fetchSessions(series, season: season, event: event, client: app.client)
            // Not every finished race's last file says so (older WEC rounds): a race that
            // started two days ago is over, and must not be refetched every five minutes.
            let cutoff = Date().addingTimeInterval(-2 * 24 * 3600)
            for index in sessions.indices where sessions[index].type == "race" && !sessions[index].isFinal {
                if let start = sessions[index].localStart, start < cutoff { sessions[index].isFinal = true }
            }
            let raceFinal = sessions.contains { $0.type == "race" && $0.isFinal }
            try? await app.kv.setJSON(cacheKey, value: sessions, ttl: raceFinal ? 400 * 24 * 3600 : 5 * 60)
            return sessions
        } catch {
            logger.warning("Al Kamel event fetch failed", metadata: ["series": "\(series.rawValue)", "event": "\(path)", "error": "\(error)"])
            return []
        }
    }

    private static func fetchSessions(_ series: AlKamelSeries, season: String, event: String, client: some Client) async throws -> [AlKamelSession] {
        let files = try await eventFiles(series, season: season, event: event, client: client)
        // Group by session folder: the path component after the championship folder.
        var bySession: [String: [String]] = [:]
        for file in files {
            let parts = file.split(separator: "/").map(String.init)
            guard let champ = parts.firstIndex(where: series.isChampionship), champ + 1 < parts.count else { continue }
            bySession[parts[champ + 1], default: []].append(file)
        }
        var sessions: [AlKamelSession] = []
        for (folder, files) in bySession {
            guard let (start, name) = AlKamelParse.sessionFolder(folder), let type = AlKamelParse.sessionType(name) else { continue }
            guard let pick = resultFile(series, files: files) else { continue }
            do {
                let body = data(try await get(url(series, pick.path), client: client))
                let isRace = type == "race"
                var duration: Double?
                let entries: [AlKamelEntry]
                if series == .imsa {
                    (entries, duration) = try AlKamelParse.imsaEntries(body, isRace: isRace)
                } else {
                    entries = AlKamelParse.wecEntries(body, isRace: isRace)
                }
                if isRace, duration == nil { duration = raceDuration(event: event, entries: entries) }
                sessions.append(AlKamelSession(folder: folder, name: name, type: type, localStart: start, entries: entries,
                                               hour: pick.hour, isFinal: pick.isFinal, duration: isRace ? duration : nil))
            } catch {
                logger.warning("Al Kamel result parse failed", metadata: ["file": "\(pick.path)", "error": "\(error)"])
            }
        }
        return sessions.sorted { ($0.localStart ?? .distantFuture) < ($1.localStart ?? .distantFuture) }
    }

    /// All result files of an event. IMSA: walk the listings (the race's latest hour
    /// folder only). WEC: the event page links every file.
    private static func eventFiles(_ series: AlKamelSeries, season: String, event: String, client: some Client) async throws -> [String] {
        switch series {
        case .wec:
            let html = try await wecEventPage(season: season, event: event, client: client)
            return AlKamelParse.links(in: html).filter { $0.hasPrefix("Results/") }.map { $0.removingPercentEncoding ?? $0 }
        case .imsa:
            let eventPath = "Results/\(season)/\(event)"
            guard let champ = try await imsaListing(eventPath, client: client).first(where: { series.isChampionship(($0 as NSString).lastPathComponent) }) else {
                return []
            }
            var files: [String] = []
            for folder in try await imsaListing(champ, client: client) {
                let name = (folder as NSString).lastPathComponent
                guard let parsed = AlKamelParse.sessionFolder(name), AlKamelParse.sessionType(parsed.name) != nil else { continue }
                let contents = try await imsaListing(folder, client: client)
                files += contents
                // Endurance races publish hour folders; the latest holds the latest classification.
                let hours = contents.filter { hourNumber(($0 as NSString).lastPathComponent) != nil }
                if let latest = hours.max(by: { hourNumber(($0 as NSString).lastPathComponent)! < hourNumber(($1 as NSString).lastPathComponent)! }) {
                    files += try await imsaListing(latest, client: client)
                }
            }
            return files
        }
    }

    struct Pick { let path: String; let hour: Int?; let isFinal: Bool }

    /// The classification to read for a session: overall results, the most final mark,
    /// and for a race the latest hour.
    static func resultFile(_ series: AlKamelSeries, files: [String]) -> Pick? {
        let candidates = files.filter { file in
            let name = (file as NSString).lastPathComponent.lowercased()
            switch series {
            case .imsa:
                return name.hasSuffix(".json") && (name.contains("_results_") || name.contains("results by hour_"))
                    && !name.contains("class")
            case .wec:
                return name.hasSuffix("csv") && name.contains("classification") && !name.contains("category")
            }
        }
        guard !candidates.isEmpty else { return nil }
        func hour(_ file: String) -> Int {
            file.split(separator: "/").compactMap { hourNumber(String($0)) }.last ?? 0
        }
        // The full final set lands in the last hour folder; prefer the overall result
        // there, then the hour's own classification.
        let best = candidates.max { lhs, rhs in
            (hour(lhs), AlKamelParse.markRank(lhs), lhs.contains("by Hour") ? 0 : 1)
                < (hour(rhs), AlKamelParse.markRank(rhs), rhs.contains("by Hour") ? 0 : 1)
        }!
        let h = hour(best)
        let rank = AlKamelParse.markRank(best)
        // IMSA: an "Unofficial" overall result (not an hourly one) only exists once the
        // session is over; WEC marks the last file "Final".
        let final = series == .wec ? rank >= 2 : (rank >= 3 || (!best.contains("by Hour") && rank >= 1) || (h == 0 && rank == 0))
        return Pick(path: best, hour: h > 0 ? h : nil, isFinal: final)
    }

    static func hourNumber(_ folder: String) -> Int? {
        guard let range = folder.range(of: #"Hour\s*(\d+)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return Int(folder[range].filter(\.isNumber))
    }

    /// WEC states race length only in the event name ("6 Hours of Spa", "24 Hours of Le Mans").
    static func raceDuration(event: String, entries: [AlKamelEntry]) -> Double? {
        let lowered = event.lowercased()
        if lowered.contains("le mans") { return 24 * 3600 }
        if lowered.contains("qatar") { return 10 * 3600 }
        // A finished race's winner time rounds to its scheduled length.
        if let winner = entries.first?.time {
            let seconds = AlKamelParse.seconds(winner)
            if seconds.isFinite, seconds > 3600 { return (seconds / 3600).rounded(.down) * 3600 }
        }
        return 6 * 3600
    }

    // MARK: - Schedule

    static func scheduleGames(_ series: AlKamelSeries, app: Application, isDebug: Bool, now: Date = Date()) async throws -> [Game] {
        let client = app.client
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        var weekends: [MotorsportWeekend] = []
        var events: [(season: String, event: String)] = []
        for season in [year - 1, year] {
            do {
                weekends += MotorsportWeekends.group(try await MotorsportWeekends.events(league: series.league, season: season, client: client))
            } catch {
                logger.warning("\(series.rawValue) TheSportsDB fetch failed", metadata: ["season": "\(season)", "error": "\(error)"])
                if season == year { throw error }
            }
            if let folder = try? await seasonFolder(series, year: season, client: client),
               let list = try? await self.events(series, season: folder, client: client) {
                events += list.map { (folder, $0) }
            }
        }

        // Each Al Kamel event's sessions (cached), keyed by its race's local day.
        var eventSessions: [(path: String, sessions: [AlKamelSession])] = []
        for (season, event) in events {
            let sessions = await self.sessions(series, season: season, event: event, app: app, isDebug: isDebug)
            if sessions.contains(where: { $0.type == "race" }) {
                eventSessions.append(("Results/\(season)/\(event)", sessions))
            }
        }

        var cached: [CachedWeekend] = []
        var games: [Game] = []
        for weekend in weekends {
            let match = matchEvent(weekend, eventSessions)
            let sessions = match?.sessions ?? []
            games.append(MotorsportGameBuilder.enduranceGame(series: series, weekend: weekend, sessions: sessions, now: now, detail: .compact))
            cached.append(CachedWeekend(weekend: cachedWeekend(weekend), eventPath: match?.path))
        }
        try? await app.kv.setJSON(weekendsKey(series, isDebug: isDebug), value: cached, ttl: 3 * 24 * 3600)
        logger.info("\(series.rawValue) schedule built", metadata: [
            "weekends": "\(games.count)", "events": "\(events.count)", "matched": "\(cached.filter { $0.eventPath != nil }.count)"
        ])
        return games
    }

    /// The Al Kamel event whose race falls within a day and a half of the weekend's race.
    static func matchEvent(_ weekend: MotorsportWeekend, _ events: [(path: String, sessions: [AlKamelSession])]) -> (path: String, sessions: [AlKamelSession])? {
        guard let raceDay = weekend.race.start else { return nil }
        return events.min { lhs, rhs in
            distance(lhs.sessions, raceDay) < distance(rhs.sessions, raceDay)
        }.flatMap { distance($0.sessions, raceDay) < 36 * 3600 ? $0 : nil }
    }

    private static func distance(_ sessions: [AlKamelSession], _ raceDay: Date) -> TimeInterval {
        guard let local = sessions.last(where: { $0.type == "race" })?.localStart else { return .infinity }
        return abs(local.timeIntervalSince(raceDay))
    }

    private static func cachedWeekend(_ weekend: MotorsportWeekend) -> IndyCarService.CachedWeekend {
        IndyCarService.CachedWeekend(
            race: .init(id: weekend.race.idEvent, name: weekend.race.strEvent, start: weekend.race.start, venue: weekend.venue, round: weekend.race.intRound),
            sessions: weekend.sessions.map { .init(id: $0.event.idEvent, type: $0.type, name: $0.name, start: $0.event.start) },
            espnID: nil
        )
    }

    // MARK: - Live / detail

    static func liveGames(_ series: AlKamelSeries, app: Application, isDebug: Bool, now: Date = Date()) async -> [Game] {
        let weekends = ((try? await app.kv.getJSON(weekendsKey(series, isDebug: isDebug), as: [CachedWeekend].self)) ?? [])
            .filter { MotorsportGameBuilder.isActive($0.weekend, now: now, raceLength: 26 * 3600) }
        guard !weekends.isEmpty else { return [] }
        var games: [Game] = []
        for cached in weekends {
            let sessions = await liveSessions(series, cached: cached, app: app, isDebug: isDebug, now: now)
            games.append(MotorsportGameBuilder.enduranceGame(series: series, weekend: cached.weekend.weekend, sessions: sessions, now: now, detail: .live))
        }
        return games
    }

    /// The weekend's sessions; during a race weekend the event may not have been
    /// matched yet (no results when the schedule was built), so look it up again.
    private static func liveSessions(_ series: AlKamelSeries, cached: CachedWeekend, app: Application, isDebug: Bool, now: Date) async -> [AlKamelSession] {
        if let path = cached.eventPath {
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count == 3 else { return [] }
            return await sessions(series, season: parts[1], event: parts[2], app: app, isDebug: isDebug)
        }
        // This runs on every live tick until the first results appear: the season's event
        // list is cached for ten minutes rather than re-listed each time.
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        let listKey = key("AlKamel \(series.rawValue) Event List \(year)", isDebug: isDebug)
        var list = try? await app.kv.getJSON(listKey, as: [String].self)
        if list == nil, let season = try? await seasonFolder(series, year: year, client: app.client),
           let events = try? await self.events(series, season: season, client: app.client) {
            list = events.map { "\(season)/\($0)" }
            try? await app.kv.setJSON(listKey, value: list, ttl: 10 * 60)
        }
        guard let latestPath = list?.last else { return [] }
        let parts = latestPath.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }
        let (season, latest) = (parts[0], parts[1])
        let sessions = await self.sessions(series, season: season, event: latest, app: app, isDebug: isDebug)
        // Only if it's this weekend's event: its first session within the weekend.
        guard let first = sessions.first?.localStart, let raceStart = cached.weekend.race.start,
              abs(first.timeIntervalSince(raceStart)) < 5 * 24 * 3600 else { return [] }
        return sessions
    }

    static func raceDetail(_ series: AlKamelSeries, tsdbRaceID: String, app: Application, isDebug: Bool, now: Date = Date()) async throws -> NASCARRaceDetail {
        let weekends = (try? await app.kv.getJSON(weekendsKey(series, isDebug: isDebug), as: [CachedWeekend].self)) ?? []
        guard let cached = weekends.first(where: { $0.weekend.race.id == tsdbRaceID }) else { throw Abort(.notFound) }
        let sessions = await liveSessions(series, cached: cached, app: app, isDebug: isDebug, now: now)
        let game = MotorsportGameBuilder.enduranceGame(series: series, weekend: cached.weekend.weekend, sessions: sessions, now: now, detail: .full)
        return NASCARRaceDetail(raceID: 0, sessions: game.sessions)
    }

    // MARK: - Standings (IMSA)

    /// IMSA's drivers' standings per class, from the points JSON in the latest event.
    /// WEC publishes standings as PDF only.
    static func standings(_ series: AlKamelSeries, app: Application, isDebug: Bool, now: Date = Date()) async throws -> ClassStandings {
        guard series == .imsa else { throw Abort(.notFound, reason: "WEC standings are PDF only") }
        let key = standingsKey(series, isDebug: isDebug)
        if let cached = try? await app.kv.getJSON(key, as: ClassStandings.self) { return cached }
        let client = app.client
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        guard let season = try await seasonFolder(.imsa, year: year, client: client) else { throw Abort(.notFound) }
        // Newest event with a points folder.
        for event in try await events(.imsa, season: season, client: client).reversed() {
            let eventPath = "Results/\(season)/\(event)"
            guard let champ = try? await imsaListing(eventPath, client: client).first(where: { AlKamelSeries.imsa.isChampionship(($0 as NSString).lastPathComponent) }),
                  let contents = try? await imsaListing(champ, client: client) else { continue }
            // "Points Data - Provisional" (also "POINTS DATA", "Points Data - Offiical"); not the PDFs.
            let pointsFolders = contents.filter { ($0 as NSString).lastPathComponent.lowercased().hasPrefix("points data") }
            guard let points = pointsFolders.max(by: { AlKamelParse.markRank($0) < AlKamelParse.markRank($1) }),
                  let files = try? await imsaListing(points, client: client) else { continue }
            var classes: [ClassStandings.ClassTable] = []
            for file in files.sorted() {
                let name = (file as NSString).lastPathComponent
                // "IWSC 01 GTP Drivers.json"
                guard let range = name.range(of: #"^IWSC \d+ (.+) Drivers\.json$"#, options: [.regularExpression, .caseInsensitive]) else { continue }
                let className = String(name[range]).replacingOccurrences(of: #"^IWSC \d+ "#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #" Drivers\.json$"#, with: "", options: [.regularExpression, .caseInsensitive])
                guard let body = try? data(await get(url(.imsa, file), client: client)),
                      let decoded = try? JSONDecoder().decode(AlKamelParse.IMSAPoints.self, from: AlKamelParse.stripBOM(body)) else { continue }
                let leader = Int(decoded.classification.first?.totalPoints ?? 0)
                let drivers = decoded.classification.enumerated().map { index, row in
                    NASCARStandingsEntry(driverID: index, position: row.position ?? index + 1, name: row.key, carNumber: "",
                                         points: Int(row.totalPoints ?? 0), behindLeader: Int(row.totalPoints ?? 0) - leader,
                                         inPlayoffs: false, wins: 0, top5: 0, top10: 0, poles: 0, stageWins: 0,
                                         lapsLed: 0, starts: 0, dnf: 0, movement: 0)
                }
                classes.append(.init(name: className, drivers: drivers))
            }
            guard !classes.isEmpty else { continue }
            let standings = ClassStandings(season: year, classes: classes)
            try? await app.kv.setJSON(key, value: standings, ttl: 60 * 60)
            return standings
        }
        throw Abort(.notFound)
    }
}
