//
//  PublicWebController.swift
//
//  Public, unauthenticated web surface: SEO schedule pages, the `/g/:id` game page,
//  subscribable ICS feeds, `/sitemap.xml` and `/robots.txt`.
//
//  - No API key: these are meant for browsers, crawlers and calendar apps. They sit
//    behind their own per-IP rate limit (`RateLimitMiddleware`, fail-open like the rest).
//  - No upstream calls and no extra Redis reads: data comes from `PublicScheduleIndex`,
//    built from the shared in-process schedule snapshot.
//  - Rendered output is cached per path for the life of an index generation (and at most
//    an hour, since "upcoming vs recent" moves with the clock). Responses carry a strong
//    ETag of the body and honour `If-None-Match`.
//

import Foundation
import Vapor
import SportsCalModel

/// Rendered bodies, keyed by route + ID, stamped with the index generation and hour they
/// were built for.
actor PublicRenderCache {
    static let shared = PublicRenderCache()
    static let maxEntries = 4000

    struct Entry {
        let generation: Int
        let hour: Int
        let body: String
        let etag: String
    }

    private var entries: [String: Entry] = [:]

    func get(_ key: String, generation: Int, hour: Int) -> Entry? {
        guard let hit = entries[key], hit.generation == generation, hit.hour == hour else { return nil }
        return hit
    }

    func put(_ key: String, _ entry: Entry) {
        if entries.count >= Self.maxEntries { entries = [:] }
        entries[key] = entry
    }

    func reset() { entries = [:] }
}

struct PublicWebController: RouteCollection {
    let site: PublicSite

    func boot(routes: RoutesBuilder) throws {
        // Pages: generous for a person, tight enough that a scraper can't spin the CPU.
        // Browsers send no X-Install-ID, so the IP ceiling is the real limit; without it
        // a made-up install ID per request walked straight past the per-identity bucket.
        let pages = routes.grouped(RateLimitMiddleware(limit: 120, windowSeconds: 60, keyPrefix: "rl:web", ipCeiling: 120))
        pages.get("team", ":teamID", use: team)
        pages.get("team", ":teamID", ":slug", use: team)
        pages.get("league", ":leagueID", use: league)
        pages.get("league", ":leagueID", ":slug", use: league)
        pages.get("g", ":id", use: game)
        pages.get("sitemap.xml", use: sitemap)
        pages.get("robots.txt", use: robots)

        // Feeds: Google Calendar fetches every subscriber's feeds from a small pool of
        // shared IPs, so the per-IP limit here is much higher than for pages.
        let feeds = routes.grouped(RateLimitMiddleware(limit: 1200, windowSeconds: 60, keyPrefix: "rl:cal", ipCeiling: 1200))
        feeds.get("cal", "team", ":file", use: teamFeed)
        feeds.get("cal", "league", ":file", use: leagueFeed)
    }

    // MARK: - Handlers

    func team(_ req: Request) async throws -> Response {
        guard let id = req.parameters.get("teamID"), WebEscape.isSafeID(id) else { throw Abort(.notFound) }
        let schedule = try await currentPublicSchedule(req)
        guard let team = schedule.teams[id] else { throw Abort(.notFound) }
        if let redirect = canonicalRedirect(req, slug: team.slug, path: site.teamPath(team)) { return redirect }
        return await cached(req, key: "team:" + id, schedule: schedule, contentType: Self.htmlType, maxAge: 300) {
            PublicPages.teamPage(team, schedule: schedule, site: site, now: Date())
        }
    }

    func league(_ req: Request) async throws -> Response {
        guard let id = req.parameters.get("leagueID"), WebEscape.isSafeID(id) else { throw Abort(.notFound) }
        let schedule = try await currentPublicSchedule(req)
        guard let league = schedule.leagues[id] else { throw Abort(.notFound) }
        if let redirect = canonicalRedirect(req, slug: league.slug, path: site.leaguePath(league)) { return redirect }
        return await cached(req, key: "league:" + id, schedule: schedule, contentType: Self.htmlType, maxAge: 300) {
            PublicPages.leaguePage(league, schedule: schedule, site: site, now: Date())
        }
    }

    func game(_ req: Request) async throws -> Response {
        guard let id = req.parameters.get("id"), WebEscape.isSafeID(id) else {
            return Self.html(PublicPages.gameFallbackPage(id: "", site: site), maxAge: 300)
        }
        // A shared link must always land somewhere: if the schedule can't be read or
        // doesn't have this game, serve the App Store fallback rather than an error.
        guard let schedule = try? await currentPublicSchedule(req), let game = schedule.games[id] else {
            return Self.html(PublicPages.gameFallbackPage(id: id, site: site), maxAge: 300)
        }
        return await cached(req, key: "game:" + id, schedule: schedule, contentType: Self.htmlType, maxAge: 60) {
            PublicPages.gamePage(game, schedule: schedule, site: site, now: Date())
        }
    }

    func sitemap(_ req: Request) async throws -> Response {
        let schedule = try await currentPublicSchedule(req)
        return await cached(req, key: "sitemap", schedule: schedule, contentType: HTTPMediaType(type: "application", subType: "xml", parameters: ["charset": "utf-8"]), maxAge: 3600) {
            PublicPages.sitemap(schedule, site: site)
        }
    }

    func robots(_ req: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.contentType = .plainText
        headers.replaceOrAdd(name: .cacheControl, value: "public, max-age=86400")
        return Response(status: .ok, headers: headers, body: .init(string: PublicPages.robots(site: site)))
    }

    func teamFeed(_ req: Request) async throws -> Response {
        guard let id = Self.feedID(req.parameters.get("file")) else { throw Abort(.notFound) }
        let schedule = try await currentPublicSchedule(req)
        guard let team = schedule.teams[id] else {
            // A team with nothing in the window (the offseason, before TheSportsDB posts
            // the next season) still answers with an empty calendar: a 404 made Calendar
            // fail the subscription, or drop one that already existed.
            return Self.emptyCalendar()
        }
        return await cached(req, key: "cal:team:" + id, schedule: schedule, contentType: Self.calendarType, maxAge: 3600) {
            PublicPages.teamCalendar(team, site: site, now: Date()).render(stamp: Self.dayStamp())
        }
    }

    func leagueFeed(_ req: Request) async throws -> Response {
        guard let id = Self.feedID(req.parameters.get("file")) else { throw Abort(.notFound) }
        let schedule = try await currentPublicSchedule(req)
        guard let league = schedule.leagues[id] else { return Self.emptyCalendar() }
        return await cached(req, key: "cal:league:" + id, schedule: schedule, contentType: Self.calendarType, maxAge: 3600) {
            PublicPages.leagueCalendar(league, site: site, now: Date()).render(stamp: Self.dayStamp())
        }
    }

    // MARK: - Plumbing

    static let htmlType = HTTPMediaType(type: "text", subType: "html", parameters: ["charset": "utf-8"])
    static let calendarType = HTTPMediaType(type: "text", subType: "calendar", parameters: ["charset": "utf-8"])

    /// "134867.ics" → "134867".
    /// A valid, eventless VCALENDAR, cached for an hour like a real feed.
    static func emptyCalendar() -> Response {
        let body = ICSCalendar(name: PublicSite.brand, description: nil, url: nil, events: [])
            .render(stamp: dayStamp())
        var headers = HTTPHeaders()
        headers.contentType = calendarType
        headers.replaceOrAdd(name: .cacheControl, value: "public, max-age=3600")
        return Response(status: .ok, headers: headers, body: .init(string: body))
    }

    static func feedID(_ file: String?) -> String? {
        guard let file, file.hasSuffix(".ics") else { return nil }
        let id = String(file.dropLast(4))
        return WebEscape.isSafeID(id) ? id : nil
    }

    /// DTSTAMP for feed events: the start of the current UTC day. Stable within a day so
    /// an unchanged schedule renders byte-identical feeds (and keeps its ETag).
    static func dayStamp(_ now: Date = Date()) -> Date {
        let seconds = floor(now.timeIntervalSince1970 / 86_400) * 86_400
        return Date(timeIntervalSince1970: seconds)
    }

    func currentPublicSchedule(_ req: Request) async throws -> PublicSchedule {
        let raw = try await currentSchedule(req)
        return await PublicScheduleIndex.shared.current(source: raw.value, version: raw.version, calendar: raw.calendar)
    }

    /// 301 to the canonical slug URL when the request's slug is missing or stale (a
    /// renamed team keeps its ID, so old links still resolve).
    func canonicalRedirect(_ req: Request, slug: String, path: String) -> Response? {
        guard !slug.isEmpty else { return nil }
        if req.parameters.get("slug") == slug { return nil }
        return req.redirect(to: path, redirectType: .permanent)
    }

    func cached(_ req: Request, key: String, schedule: PublicSchedule, contentType: HTTPMediaType, maxAge: Int, render: () -> String) async -> Response {
        let hour = Int(Date().timeIntervalSince1970 / 3600)
        let entry: PublicRenderCache.Entry
        if let hit = await PublicRenderCache.shared.get(key, generation: schedule.generation, hour: hour) {
            entry = hit
        } else {
            let body = render()
            let etag = "\"" + PayloadVersion.of(body) + "\""
            entry = PublicRenderCache.Entry(generation: schedule.generation, hour: hour, body: body, etag: etag)
            await PublicRenderCache.shared.put(key, entry)
        }

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .eTag, value: entry.etag)
        headers.replaceOrAdd(name: .cacheControl, value: "public, max-age=" + String(maxAge))
        if HTTPCaching.notModified(req, etag: entry.etag) {
            return Response(status: .notModified, headers: headers)
        }
        headers.contentType = contentType
        return Response(status: .ok, headers: headers, body: .init(string: entry.body))
    }

    static func html(_ body: String, maxAge: Int) -> Response {
        var headers = HTTPHeaders()
        headers.contentType = htmlType
        headers.replaceOrAdd(name: .cacheControl, value: "public, max-age=" + String(maxAge))
        return Response(status: .ok, headers: headers, body: .init(string: body))
    }
}
