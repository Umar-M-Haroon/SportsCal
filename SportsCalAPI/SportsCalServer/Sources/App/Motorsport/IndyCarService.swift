//
//  IndyCarService.swift
//
//  IndyCar Series weekends. TheSportsDB has the shape of every weekend (practices,
//  qualifying, the race, venue); ESPN has the race: finishing order and status on its
//  scoreboard, and per car (number, team, engine, laps led, pit stops, start position)
//  in its core API. The core API costs two requests per car, so a race's detail is
//  fetched once it's final and kept, and its entry list (car numbers, teams) is
//  reused for the live order of the races after it.
//

import Foundation
import Vapor
import SportsCalModel

enum IndyCarService {
    static let league = Leagues.indycar
    private static let logger = Logger(label: "com.sportscal.indycar")

    static func eventID(tsdbRaceID: String) -> String { "indycar-\(tsdbRaceID)" }

    // MARK: - Cache keys

    private static func key(_ name: String, isDebug: Bool) -> String { (isDebug ? "debug-" : "") + name }
    static func weekendsKey(isDebug: Bool) -> String { key("IndyCar Weekends", isDebug: isDebug) }
    static func detailKey(espnID: String, isDebug: Bool) -> String { key("IndyCar Race Detail \(espnID)", isDebug: isDebug) }
    static func entryListKey(isDebug: Bool) -> String { key("IndyCar Entry List", isDebug: isDebug) }
    static func standingsKey(isDebug: Bool) -> String { key("IndyCar Standings", isDebug: isDebug) }

    /// A weekend as cached for the live path: TheSportsDB's events plus the ESPN race ID.
    struct CachedWeekend: Codable {
        let race: CachedEvent
        let sessions: [CachedSession]
        let espnID: String?

        struct CachedEvent: Codable { let id: String; let name: String; let start: Date?; let venue: String?; let round: String? }
        struct CachedSession: Codable { let id: String; let type: String; let name: String; let start: Date? }
    }

    // MARK: - ESPN

    static func scoreboard(year: Int?, client: some Client) async throws -> Scoreboard {
        let dates = year.map { "?dates=\($0)" } ?? ""
        let response = try await ESPNNetworking.performGet(client, URI(string: "https://site.api.espn.com/apis/site/v2/sports/racing/irl/scoreboard\(dates)"))
        return try response.content.decode(Scoreboard.self)
    }

    /// One car in an ESPN race, from the core API.
    struct ESPNCar: Codable {
        let id: String
        let order: Int
        let startOrder: Int?
        let winner: Bool?
        let number: String?
        let manufacturer: String?
        let team: String?
        let sponsor: String?
        let lapsLed: Int?
        let lapsCompleted: Int?
        let lapsBehind: Int?
        let behindTime: String?
        let points: Int?
        let pits: Int?
    }

    private struct CoreList: Decodable { let items: [Item]; struct Item: Decodable { let ref: String; enum CodingKeys: String, CodingKey { case ref = "$ref" } } }
    private struct CoreCompetitor: Decodable {
        let id: String
        let order: Int?
        let startOrder: Int?
        let winner: Bool?
        let vehicle: Vehicle?
        let statistics: Ref?
        struct Vehicle: Decodable { let number: String?; let manufacturer: String?; let team: String?; let sponsor: String? }
        struct Ref: Decodable { let ref: String; enum CodingKeys: String, CodingKey { case ref = "$ref" } }
    }
    private struct CoreStats: Decodable {
        let splits: Splits
        struct Splits: Decodable { let categories: [Category] }
        struct Category: Decodable { let stats: [Stat] }
        struct Stat: Decodable { let name: String; let value: Double?; let displayValue: String? }
    }

    /// Every car in a race with its core-API detail. ~50 requests: only for races that
    /// are over (cached for good) or explicitly opened.
    static func cars(espnID: String, client: some Client) async throws -> [ESPNCar] {
        let base = "https://sports.core.api.espn.com/v2/sports/racing/leagues/irl/events/\(espnID)/competitions/\(espnID)"
        let list = try await ESPNNetworking.performGet(client, URI(string: "\(base)/competitors?limit=60")).content.decode(CoreList.self)
        return try await withThrowingTaskGroup(of: ESPNCar?.self) { group in
            var pending = list.items.makeIterator()
            func addNext() -> Bool {
                guard let item = pending.next() else { return false }
                group.addTask { try? await car(ref: item.ref, client: client) }
                return true
            }
            var inFlight = 0
            while inFlight < 6, addNext() { inFlight += 1 }
            var cars: [ESPNCar] = []
            for try await car in group {
                if let car { cars.append(car) }
                _ = addNext()
            }
            return cars.sorted { $0.order < $1.order }
        }
    }

    private static func car(ref: String, client: some Client) async throws -> ESPNCar {
        let secure = ref.replacingOccurrences(of: "http://", with: "https://")
        let competitor = try await ESPNNetworking.performGet(client, URI(string: secure)).content.decode(CoreCompetitor.self)
        var stats: [String: CoreStats.Stat] = [:]
        if let statsRef = competitor.statistics?.ref {
            let decoded = try? await ESPNNetworking.performGet(client, URI(string: statsRef.replacingOccurrences(of: "http://", with: "https://")))
                .content.decode(CoreStats.self)
            for category in decoded?.splits.categories ?? [] {
                for stat in category.stats { stats[stat.name] = stat }
            }
        }
        func int(_ name: String) -> Int? { stats[name]?.value.map { Int($0) } }
        return ESPNCar(
            id: competitor.id, order: competitor.order ?? 0, startOrder: competitor.startOrder, winner: competitor.winner,
            number: competitor.vehicle?.number, manufacturer: competitor.vehicle?.manufacturer,
            team: competitor.vehicle?.team, sponsor: competitor.vehicle?.sponsor,
            lapsLed: int("lapsLead"), lapsCompleted: int("lapsCompleted"), lapsBehind: int("behindLaps"),
            behindTime: stats["behindTime"]?.displayValue, points: int("championshipPts"), pits: int("pitsTaken")
        )
    }

    // MARK: - Schedule

    static func scheduleGames(app: Application, isDebug: Bool, now: Date = Date()) async throws -> [Game] {
        let client = app.client
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        var weekends: [MotorsportWeekend] = []
        var espnEvents: [Event] = []
        for season in [year - 1, year] {
            do {
                weekends += MotorsportWeekends.group(try await MotorsportWeekends.events(league: league, season: season, client: client))
            } catch {
                logger.warning("IndyCar TheSportsDB fetch failed", metadata: ["season": "\(season)", "error": "\(error)"])
                if season == year { throw error }
            }
            if let board = try? await scoreboard(year: season, client: client) { espnEvents += board.events }
        }

        let matched = weekends.map { ($0, espnEvent(for: $0, in: espnEvents)) }
        await storeWeekends(matched, app: app, isDebug: isDebug)

        // Fill in the detail of the most recent finished races (the rest load on demand).
        let finishedIDs = matched.compactMap { $0.1 }.filter { $0.status?.type.completed == true }.map(\.id)
        for espnID in finishedIDs.suffix(3) {
            _ = await cachedOrFetchedCars(espnID: espnID, app: app, isDebug: isDebug, fetchIfMissing: true)
        }
        let entryList = await entryList(app: app, isDebug: isDebug)

        var games: [Game] = []
        for (weekend, espn) in matched {
            var cars: [ESPNCar] = []
            if let espn {
                cars = await cachedOrFetchedCars(espnID: espn.id, app: app, isDebug: isDebug, fetchIfMissing: false) ?? []
            }
            games.append(MotorsportGameBuilder.indyCarGame(weekend: weekend, espn: espn, cars: cars, entryList: entryList,
                                                           now: now, detail: .compact))
        }
        logger.info("IndyCar schedule built", metadata: ["weekends": "\(games.count)", "espn": "\(espnEvents.count)"])
        return games
    }

    /// The ESPN race for a TheSportsDB weekend: the board's event within a day of the
    /// race start, else one whose name shares the race's.
    static func espnEvent(for weekend: MotorsportWeekend, in events: [Event]) -> Event? {
        guard let start = weekend.race.start else { return nil }
        let near = events.filter { event in
            guard let date = DateParsers.parse(event.date) else { return false }
            return abs(date.timeIntervalSince(start)) < 36 * 3600
        }
        // Doubleheaders (Milwaukee) put two races a day apart: the closer start wins.
        return near.min { lhs, rhs in
            abs((DateParsers.parse(lhs.date) ?? .distantPast).timeIntervalSince(start))
                < abs((DateParsers.parse(rhs.date) ?? .distantPast).timeIntervalSince(start))
        }
    }

    private static func storeWeekends(_ matched: [(MotorsportWeekend, Event?)], app: Application, isDebug: Bool) async {
        let cached = matched.map { weekend, espn in
            CachedWeekend(
                race: .init(id: weekend.race.idEvent, name: weekend.race.strEvent, start: weekend.race.start, venue: weekend.venue, round: weekend.race.intRound),
                sessions: weekend.sessions.map { .init(id: $0.event.idEvent, type: $0.type, name: $0.name, start: $0.event.start) },
                espnID: espn?.id
            )
        }
        try? await app.kv.setJSON(weekendsKey(isDebug: isDebug), value: cached, ttl: 3 * 24 * 3600)
    }

    static func cachedWeekends(app: Application, isDebug: Bool) async -> [CachedWeekend] {
        (try? await app.kv.getJSON(weekendsKey(isDebug: isDebug), as: [CachedWeekend].self)) ?? []
    }

    /// A race's cars: cached once final; otherwise fetched only when asked.
    static func cachedOrFetchedCars(espnID: String, app: Application, isDebug: Bool, fetchIfMissing: Bool) async -> [ESPNCar]? {
        let key = detailKey(espnID: espnID, isDebug: isDebug)
        if let cached = try? await app.kv.getJSON(key, as: [ESPNCar].self) { return cached }
        guard fetchIfMissing, let cars = try? await cars(espnID: espnID, client: app.client), !cars.isEmpty else { return nil }
        try? await app.kv.setJSON(key, value: cars, ttl: 400 * 24 * 3600)
        // The newest race's cars are the season's entry list for the live order.
        try? await app.kv.setJSON(entryListKey(isDebug: isDebug), value: cars, ttl: 200 * 24 * 3600)
        return cars
    }

    static func entryList(app: Application, isDebug: Bool) async -> [ESPNCar] {
        (try? await app.kv.getJSON(entryListKey(isDebug: isDebug), as: [ESPNCar].self)) ?? []
    }

    // MARK: - Live

    /// Games for a weekend in progress, rebuilt from ESPN's current board.
    static func liveGames(app: Application, isDebug: Bool, now: Date = Date()) async -> [Game] {
        let weekends = await cachedWeekends(app: app, isDebug: isDebug).filter { MotorsportGameBuilder.isActive($0, now: now) }
        guard !weekends.isEmpty else { return [] }
        let board = try? await scoreboard(year: nil, client: app.client)
        let entryList = await entryList(app: app, isDebug: isDebug)
        return weekends.map { cached in
            let espn = board?.events.first { $0.id == cached.espnID }
            return MotorsportGameBuilder.indyCarGame(weekend: cached.weekend, espn: espn, cars: [], entryList: entryList, now: now, detail: .live)
        }
    }

    // MARK: - Detail / standings

    static func raceDetail(tsdbRaceID: String, app: Application, isDebug: Bool, now: Date = Date()) async throws -> NASCARRaceDetail {
        guard let cached = await cachedWeekends(app: app, isDebug: isDebug).first(where: { $0.race.id == tsdbRaceID }) else {
            throw Abort(.notFound)
        }
        var cars: [ESPNCar] = []
        var espn: Event?
        if let espnID = cached.espnID {
            cars = await cachedOrFetchedCars(espnID: espnID, app: app, isDebug: isDebug,
                                             fetchIfMissing: true) ?? []
            espn = try? await scoreboard(year: Calendar(identifier: .gregorian).component(.year, from: cached.race.start ?? now), client: app.client)
                .events.first { $0.id == espnID }
        }
        let game = MotorsportGameBuilder.indyCarGame(weekend: cached.weekend, espn: espn, cars: cars,
                                                     entryList: await entryList(app: app, isDebug: isDebug), now: now, detail: .full)
        return NASCARRaceDetail(raceID: 0, sessions: game.sessions)
    }

    static func standings(app: Application, isDebug: Bool) async throws -> NASCARStandings {
        let key = standingsKey(isDebug: isDebug)
        if let cached = try? await app.kv.getJSON(key, as: NASCARStandings.self) { return cached }
        let response = try await ESPNNetworking.performGet(app.client, URI(string: "https://site.web.api.espn.com/apis/v2/sports/racing/irl/standings"))
        let decoded = try response.content.decode(ESPNRacingStandings.self)
        let entryList = await entryList(app: app, isDebug: isDebug)
        let standings = MotorsportGameBuilder.standings(decoded, entryList: entryList)
        try? await app.kv.setJSON(key, value: standings, ttl: 30 * 60)
        return standings
    }
}

/// ESPN's racing standings (`/apis/v2/sports/racing/{league}/standings`).
struct ESPNRacingStandings: Decodable {
    let children: [Child]?
    let seasons: [Season]?

    struct Child: Decodable { let standings: Standings }
    struct Standings: Decodable { let entries: [Entry] }
    struct Entry: Decodable {
        let athlete: Athlete
        let stats: [Stat]
        struct Athlete: Decodable { let id: String?; let displayName: String }
        struct Stat: Decodable { let type: String?; let name: String?; let value: Double?; let displayValue: String? }
    }
    struct Season: Decodable { let year: Int? }
}

extension IndyCarService.CachedWeekend {
    /// Back to the grouping type the builder takes.
    var weekend: MotorsportWeekend {
        func event(_ id: String, _ name: String, _ start: Date?) -> TSDBRacingEvent {
            TSDBRacingEvent(idEvent: id, strEvent: name, strTimestamp: start.map(MotorsportWeekends.iso),
                            dateEvent: nil, strVenue: race.venue, strCountry: nil, intRound: race.round)
        }
        return MotorsportWeekend(
            race: event(race.id, race.name, race.start),
            sessions: sessions.map { .init(event: event($0.id, $0.name, $0.start), type: $0.type, name: $0.name) }
        )
    }
}
