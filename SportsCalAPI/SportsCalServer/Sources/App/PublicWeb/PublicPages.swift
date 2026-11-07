//
//  PublicPages.swift
//
//  Server-rendered public pages (team, league, game, sitemap, robots) and the ICS
//  feeds built from `PublicSchedule`. Pure functions of their inputs, so routes cache
//  the output and tests can call them directly.
//
//  Two rules hold everywhere in this file:
//  - every upstream string goes through `WebEscape.html` (or `scriptJSON` for JSON-LD)
//    before it reaches markup;
//  - strings are built one short statement at a time. The Linux release compiler has
//    failed the prod build on long `+` chains ("unable to type-check this expression in
//    reasonable time"), so no line here concatenates more than a few plain Strings.
//
//  No odds, lines or betting content, by product decision.
//

import Foundation
import SportsCalModel

struct PublicSite {
    /// e.g. "https://sportscal.app", no trailing slash.
    let baseURL: String

    static let appStoreID = "1580232928"
    static let appStoreURL = "https://apps.apple.com/app/id1580232928"
    static let brand = "Scoreline"

    init(baseURL: String) {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        self.baseURL = base.isEmpty ? "https://sportscal.app" : base
    }

    static func fromEnvironment(_ value: String?) -> PublicSite {
        PublicSite(baseURL: value ?? "https://sportscal.app")
    }

    var host: String {
        URL(string: baseURL)?.host ?? "sportscal.app"
    }

    // MARK: URLs

    func teamPath(_ team: PublicTeam) -> String {
        team.slug.isEmpty ? "/team/" + team.id : "/team/" + team.id + "/" + team.slug
    }

    func leaguePath(_ league: PublicLeague) -> String {
        league.slug.isEmpty ? "/league/" + league.id : "/league/" + league.id + "/" + league.slug
    }

    func gamePath(_ id: String) -> String { "/g/" + id }
    func teamFeedPath(_ id: String) -> String { "/cal/team/" + id + ".ics" }
    func leagueFeedPath(_ id: String) -> String { "/cal/league/" + id + ".ics" }

    func absolute(_ path: String) -> String { baseURL + path }

    /// The same URL with the `webcal` scheme, which Apple Calendar opens as a subscription.
    func webcal(_ path: String) -> String {
        var url = absolute(path)
        if url.hasPrefix("https://") {
            url = "webcal://" + url.dropFirst("https://".count)
        } else if url.hasPrefix("http://") {
            url = "webcal://" + url.dropFirst("http://".count)
        }
        return url
    }

    func googleCalendar(_ path: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = webcal(path).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return "https://calendar.google.com/calendar/render?cid=" + encoded
    }
}

enum PublicPages {
    static let upcomingLimitTeam = 120
    static let upcomingLimitLeague = 150
    static let recentLimit = 60
    static let recentWindow: TimeInterval = 30 * 86_400

    // MARK: - Team

    static func teamPage(_ team: PublicTeam, schedule: PublicSchedule, site: PublicSite, now: Date) -> String {
        let season = PublicGame.season(of: team.games, now: now) ?? yearLabel(now)
        let name = team.name
        let title = name + " Schedule " + season + " — Scores & Fixtures"
        let league = team.primaryLeagueID.flatMap { schedule.leagues[$0] }
        var description = name + " " + season + " schedule with kickoff times, live scores and recent results"
        if let league { description += " (" + league.name + ")" }
        description += ". Add every game to your calendar."

        let split = splitGames(team.games, now: now)
        let canonical = site.absolute(site.teamPath(team))

        var b = HTMLBuilder()
        b.add("<p class=\"crumb\">")
        if let league {
            b.add("<a href=\"" + WebEscape.html(site.leaguePath(league)) + "\">")
            b.add(WebEscape.html(league.name) + "</a>")
        }
        b.add("</p>")
        b.add("<h1>" + WebEscape.html(title) + "</h1>")
        b.add(calendarActions(feedPath: site.teamFeedPath(team.id), label: name, site: site))
        b.add(gamesSection("Upcoming", games: Array(split.upcoming.prefix(upcomingLimitTeam)), schedule: schedule, site: site, now: now, focusTeam: team.id))
        b.add(gamesSection("Recent results", games: Array(split.recent.prefix(recentLimit)), schedule: schedule, site: site, now: now, focusTeam: team.id))
        b.add(appCTA())

        let ld = eventsJSONLD(Array(split.upcoming.prefix(20)), site: site)
        return page(title: title, description: description, canonical: canonical, appArgument: canonical, jsonLD: ld, body: b.html, site: site)
    }

    // MARK: - League

    static func leaguePage(_ league: PublicLeague, schedule: PublicSchedule, site: PublicSite, now: Date) -> String {
        let season = PublicGame.season(of: league.games, now: now) ?? yearLabel(now)
        let title = league.name + " Schedule " + season + " — Scores & Fixtures"
        let description = league.name + " " + season + " schedule: every upcoming fixture, live scores and recent results. Subscribe to the full calendar."
        let canonical = site.absolute(site.leaguePath(league))

        var b = HTMLBuilder()
        b.add("<h1>" + WebEscape.html(title) + "</h1>")
        b.add(calendarActions(feedPath: site.leagueFeedPath(league.id), label: league.name, site: site))

        let ld: String
        if league.sport == .tennis {
            let tournaments = tennisTournaments(league.games)
            b.add(tournamentSection(tournaments, now: now))
            ld = ""
        } else {
            let split = splitGames(league.games, now: now)
            b.add(gamesSection("Upcoming", games: Array(split.upcoming.prefix(upcomingLimitLeague)), schedule: schedule, site: site, now: now, focusTeam: nil))
            b.add(gamesSection("Recent results", games: Array(split.recent.prefix(recentLimit)), schedule: schedule, site: site, now: now, focusTeam: nil))
            ld = eventsJSONLD(Array(split.upcoming.prefix(20)), site: site)
        }

        let teams = league.teamIDs.compactMap { schedule.teams[$0] }
        if !teams.isEmpty {
            b.add("<section><h2>Teams</h2><ul class=\"teams\">")
            for team in teams {
                b.add("<li><a href=\"" + WebEscape.html(site.teamPath(team)) + "\">")
                b.add(WebEscape.html(team.name) + "</a></li>")
            }
            b.add("</ul></section>")
        }
        b.add(appCTA())
        return page(title: title, description: description, canonical: canonical, appArgument: canonical, jsonLD: ld, body: b.html, site: site)
    }

    // MARK: - Game

    static func gamePage(_ game: Game, schedule: PublicSchedule, site: PublicSite, now: Date) -> String {
        let id = game.idEvent ?? ""
        let matchup = PublicGame.title(game)
        let start = PublicGame.start(game)
        var title = matchup
        if let start { title += " — " + longDate(start) }
        let league = game.idLeague.flatMap { schedule.leagues[$0] }
        var description = matchup
        if let league { description += " (" + league.name + ")" }
        description += ": start time, score and result."
        let canonical = site.absolute(site.gamePath(id))

        var b = HTMLBuilder()
        b.add("<p class=\"crumb\">")
        if let league {
            b.add("<a href=\"" + WebEscape.html(site.leaguePath(league)) + "\">")
            b.add(WebEscape.html(league.name) + "</a>")
        }
        b.add("</p>")
        b.add("<h1>" + WebEscape.html(matchup) + "</h1>")
        b.add("<div class=\"card\">")
        b.add("<p class=\"when\">" + timeTag(game, long: true) + "</p>")
        if let venue = game.venueName, !venue.isEmpty {
            b.add("<p class=\"muted\">" + WebEscape.html(venue) + "</p>")
        }
        b.add("<p class=\"status\">" + statusBadge(game, now: now) + "</p>")
        if let result = PublicGame.result(game), PublicGame.status(game, now: now) != .scheduled {
            b.add("<p class=\"score\">" + WebEscape.html(result) + "</p>")
        }
        b.add("</div>")

        if !game.isIndividualSport {
            b.add("<section><h2>Teams</h2><ul class=\"teams\">")
            b.add(teamItem(id: game.idAwayTeam, name: game.strAwayTeam, schedule: schedule, site: site))
            b.add(teamItem(id: game.idHomeTeam, name: game.strHomeTeam, schedule: schedule, site: site))
            b.add("</ul></section>")
        }
        b.add(appCTA())
        let ld = eventsJSONLD([game], site: site)
        return page(title: title, description: description, canonical: canonical, appArgument: canonical, jsonLD: ld, body: b.html, site: site)
    }

    /// For a game the index doesn't know (outside the window): the original universal-link
    /// fallback — smart banner plus a bounce to the App Store — marked noindex.
    static func gameFallbackPage(id: String, site: PublicSite) -> String {
        let argument = site.absolute(site.gamePath(id))
        var b = ""
        b += "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
        b += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
        b += "<meta name=\"robots\" content=\"noindex\">"
        b += "<meta name=\"apple-itunes-app\" content=\"app-id=" + PublicSite.appStoreID + ", app-argument=" + WebEscape.html(argument) + "\">"
        b += "<title>Game · " + PublicSite.brand + "</title>"
        b += "<meta http-equiv=\"refresh\" content=\"0; url=" + PublicSite.appStoreURL + "\">"
        b += "</head><body><p>Opening " + PublicSite.brand + "… <a href=\"" + PublicSite.appStoreURL + "\">Get the app</a>.</p></body></html>"
        return b
    }

    // MARK: - Sitemap / robots

    static func sitemap(_ schedule: PublicSchedule, site: PublicSite) -> String {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">")
        for league in schedule.leagues.values.sorted(by: { $0.id < $1.id }) {
            lines.append("<url><loc>" + WebEscape.html(site.absolute(site.leaguePath(league))) + "</loc><changefreq>daily</changefreq></url>")
        }
        for team in schedule.teams.values.sorted(by: { $0.id < $1.id }) {
            lines.append("<url><loc>" + WebEscape.html(site.absolute(site.teamPath(team))) + "</loc><changefreq>daily</changefreq></url>")
        }
        lines.append("</urlset>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func robots(site: PublicSite) -> String {
        var out = "User-agent: *\n"
        out += "Allow: /\n"
        out += "Disallow: /admin\n"
        out += "Disallow: /v2025/\n"
        out += "Disallow: /cal/\n"
        out += "Sitemap: " + site.absolute("/sitemap.xml") + "\n"
        return out
    }

    // MARK: - Calendar feeds

    static func teamCalendar(_ team: PublicTeam, site: PublicSite, now: Date) -> ICSCalendar {
        let events = feedGames(team.games, now: now).map { icsEvent($0, site: site, now: now) }
        return ICSCalendar(
            name: team.name + " · " + PublicSite.brand,
            description: team.name + " schedule and results from " + PublicSite.brand,
            url: site.absolute(site.teamPath(team)),
            events: events
        )
    }

    static func leagueCalendar(_ league: PublicLeague, site: PublicSite, now: Date) -> ICSCalendar {
        let events: [ICSEvent]
        if league.sport == .tennis {
            // Thousands of individual matches would bury a calendar; one entry per
            // tournament is what someone subscribing to "ATP" wants.
            let cutoff = now.addingTimeInterval(-recentWindow)
            events = tennisTournaments(league.games).filter { $0.end >= cutoff }.map { t in
                ICSEvent(
                    uid: tennisUID(t, league: league, site: site),
                    timing: .allDay(start: t.start, endExclusive: dayAfter(t.end)),
                    summary: t.name,
                    description: league.name + "\n" + site.absolute(site.leaguePath(league)),
                    location: nil,
                    url: site.absolute(site.leaguePath(league))
                )
            }
        } else {
            events = feedGames(league.games, now: now).map { icsEvent($0, site: site, now: now) }
        }
        return ICSCalendar(
            name: league.name + " · " + PublicSite.brand,
            description: league.name + " schedule and results from " + PublicSite.brand,
            url: site.absolute(site.leaguePath(league)),
            events: events
        )
    }

    /// Games from 30 days ago onwards.
    static func feedGames(_ games: [Game], now: Date) -> [Game] {
        let cutoff = now.addingTimeInterval(-recentWindow)
        return games.filter { game in
            guard let start = PublicGame.start(game) else { return false }
            return start >= cutoff
        }
    }

    static func icsEvent(_ game: Game, site: PublicSite, now: Date) -> ICSEvent {
        let id = game.idEvent ?? ""
        let start = PublicGame.start(game) ?? now
        let url = site.absolute(site.gamePath(id))
        let timing: ICSEvent.Timing
        if game.sportType == .golf {
            let last = PublicGame.endDate(game).map { $0.addingTimeInterval(-86_400) } ?? start
            timing = .allDay(start: start, endExclusive: dayAfter(max(last, start)))
        } else {
            timing = .timed(start: start, end: start.addingTimeInterval(PublicGame.duration(game)))
        }

        var lines: [String] = []
        if let league = game.strLeague { lines.append(league) }
        if PublicGame.isTennis(game), let tournament = game.tournamentName { lines.append(tournament) }
        let status = PublicGame.status(game, now: now)
        if status == .final, let result = PublicGame.result(game) {
            lines.append("Final: " + result)
        }
        if case .calledOff(let label) = status { lines.append(label) }
        lines.append(url)

        var cancelled = false
        if case .calledOff = status { cancelled = true }
        return ICSEvent(
            uid: id + "@" + site.host,
            timing: timing,
            summary: PublicGame.title(game),
            description: lines.joined(separator: "\n"),
            location: game.venueName,
            url: url,
            cancelled: cancelled
        )
    }

    // MARK: - Pieces

    struct Split {
        var upcoming: [Game]
        var recent: [Game]
    }

    /// Upcoming (live or not yet finished, soonest first) and recent (finished within 30
    /// days, newest first).
    static func splitGames(_ games: [Game], now: Date) -> Split {
        var upcoming: [Game] = []
        var recent: [Game] = []
        let cutoff = now.addingTimeInterval(-recentWindow)
        for game in games {
            guard let start = PublicGame.start(game) else { continue }
            let status = PublicGame.status(game, now: now)
            let isPast = status == .final || start.addingTimeInterval(PublicGame.duration(game)) < now
            if isPast {
                if start >= cutoff { recent.append(game) }
            } else {
                upcoming.append(game)
            }
        }
        return Split(upcoming: upcoming, recent: recent.reversed())
    }

    static func gamesSection(_ heading: String, games: [Game], schedule: PublicSchedule, site: PublicSite, now: Date, focusTeam: String?) -> String {
        var b = HTMLBuilder()
        b.add("<section><h2>" + WebEscape.html(heading) + "</h2>")
        if games.isEmpty {
            b.add("<p class=\"muted\">No games scheduled in this window.</p></section>")
            return b.html
        }
        b.add("<table><thead><tr><th>Date</th><th>Game</th><th>Result</th></tr></thead><tbody>")
        for game in games {
            b.add("<tr><td>" + timeTag(game, long: false) + "</td>")
            b.add("<td>" + matchupCell(game, schedule: schedule, site: site, focusTeam: focusTeam) + "</td>")
            b.add("<td>" + resultCell(game, site: site, now: now) + "</td></tr>")
        }
        b.add("</tbody></table></section>")
        return b.html
    }

    static func matchupCell(_ game: Game, schedule: PublicSchedule, site: PublicSite, focusTeam: String?) -> String {
        if PublicGame.isNamedEvent(game) || PublicGame.isTennis(game) {
            var out = WebEscape.html(PublicGame.title(game))
            if PublicGame.isTennis(game), let tournament = game.tournamentName {
                out += "<br><span class=\"muted\">" + WebEscape.html(tournament) + "</span>"
            }
            return out
        }
        let away = teamLink(id: game.idAwayTeam, name: game.strAwayTeam, schedule: schedule, site: site, focusTeam: focusTeam)
        let home = teamLink(id: game.idHomeTeam, name: game.strHomeTeam, schedule: schedule, site: site, focusTeam: focusTeam)
        var out = ""
        if PublicGame.isSoccer(game) {
            out = home + " vs " + away
        } else {
            out = away + " @ " + home
        }
        if focusTeam != nil, let league = game.strLeague, !league.isEmpty {
            out += "<br><span class=\"muted\">" + WebEscape.html(league) + "</span>"
        }
        return out
    }

    static func teamLink(id: String?, name: String, schedule: PublicSchedule, site: PublicSite, focusTeam: String?) -> String {
        let label = WebEscape.html(name)
        guard let id, id != focusTeam, let team = schedule.teams[id] else {
            return id != nil && id == focusTeam ? "<strong>" + label + "</strong>" : label
        }
        return "<a href=\"" + WebEscape.html(site.teamPath(team)) + "\">" + label + "</a>"
    }

    static func teamItem(id: String?, name: String, schedule: PublicSchedule, site: PublicSite) -> String {
        guard let id, let team = schedule.teams[id] else {
            return "<li>" + WebEscape.html(name) + "</li>"
        }
        var out = "<li><a href=\"" + WebEscape.html(site.teamPath(team)) + "\">"
        out += WebEscape.html(name) + " schedule</a></li>"
        return out
    }

    static func resultCell(_ game: Game, site: PublicSite, now: Date) -> String {
        let link = "<a href=\"" + WebEscape.html(site.gamePath(game.idEvent ?? "")) + "\">"
        let status = PublicGame.status(game, now: now)
        var text: String
        switch status {
        case .final:
            text = PublicGame.shortScore(game) ?? PublicGame.result(game) ?? "Final"
            if PublicGame.shortScore(game) != nil { text = "Final " + text }
        case .live:
            text = "Live"
        case .calledOff(let label):
            text = label
        case .scheduled:
            text = "Details"
        }
        return link + WebEscape.html(text) + "</a>"
    }

    static func statusBadge(_ game: Game, now: Date) -> String {
        switch PublicGame.status(game, now: now) {
        case .final: return "<span class=\"badge\">Final</span>"
        case .live: return "<span class=\"badge live\">Live</span>"
        case .calledOff(let label): return "<span class=\"badge\">" + WebEscape.html(label) + "</span>"
        case .scheduled: return "<span class=\"badge\">Scheduled</span>"
        }
    }

    /// A `<time>` with a UTC fallback label; the inline script rewrites it into the
    /// reader's own time zone.
    static func timeTag(_ game: Game, long: Bool) -> String {
        guard let start = PublicGame.start(game) else { return "TBD" }
        let dateOnly = game.sportType == .golf
        let iso = isoFormatter.string(from: start)
        let label: String
        if dateOnly {
            label = dayFormatter.string(from: start)
        } else {
            label = (long ? longFormatter : shortFormatter).string(from: start) + " UTC"
        }
        var out = "<time datetime=\"" + iso + "\" data-t=\""
        out += dateOnly ? "d" : (long ? "l" : "s")
        out += "\">" + WebEscape.html(label) + "</time>"
        return out
    }

    static func calendarActions(feedPath: String, label: String, site: PublicSite) -> String {
        var b = HTMLBuilder()
        b.add("<div class=\"actions\">")
        b.add("<a class=\"btn primary\" href=\"" + WebEscape.html(site.webcal(feedPath)) + "\">Add to Calendar</a>")
        b.add("<a class=\"btn\" href=\"" + WebEscape.html(site.googleCalendar(feedPath)) + "\" rel=\"nofollow\">Google Calendar</a>")
        b.add("<a class=\"btn\" href=\"" + WebEscape.html(site.absolute(feedPath)) + "\" rel=\"nofollow\">.ics</a>")
        b.add("</div>")
        b.add("<p class=\"muted small\">Subscribe once and every " + WebEscape.html(label) + " game, time change and result shows up in your calendar.</p>")
        return b.html
    }

    static func appCTA() -> String {
        var b = HTMLBuilder()
        b.add("<aside class=\"cta\"><h2>Live scores on your iPhone</h2>")
        b.add("<p>Follow every game with live scores, Live Activities and widgets in " + PublicSite.brand + ".</p>")
        b.add("<a class=\"btn primary\" href=\"" + PublicSite.appStoreURL + "\">Download on the App Store</a></aside>")
        return b.html
    }

    // MARK: - Tennis tournaments

    struct Tournament: Equatable {
        let name: String
        let start: Date
        let end: Date
    }

    static func tennisTournaments(_ games: [Game]) -> [Tournament] {
        var ranges: [String: (Date, Date)] = [:]
        for game in games {
            guard let name = game.tournamentName, !name.isEmpty, let start = PublicGame.start(game) else { continue }
            if let existing = ranges[name] {
                ranges[name] = (min(existing.0, start), max(existing.1, start))
            } else {
                ranges[name] = (start, start)
            }
        }
        let list = ranges.map { Tournament(name: $0.key, start: $0.value.0, end: $0.value.1) }
        return list.sorted { $0.start == $1.start ? $0.name < $1.name : $0.start < $1.start }
    }

    /// Keyed by tour, name and year, not the first match's date: a qualifying round added
    /// later would otherwise change the UID and duplicate the entry in subscribers' calendars.
    static func tennisUID(_ t: Tournament, league: PublicLeague, site: PublicSite) -> String {
        let year = String(ICS.utcDay(t.start).prefix(4))
        return "tennis-" + league.id + "-" + WebEscape.slug(t.name) + "-" + year + "@" + site.host
    }

    static func tournamentSection(_ tournaments: [Tournament], now: Date) -> String {
        var b = HTMLBuilder()
        b.add("<section><h2>Tournaments</h2>")
        if tournaments.isEmpty {
            b.add("<p class=\"muted\">No tournaments scheduled in this window.</p></section>")
            return b.html
        }
        b.add("<table><thead><tr><th>Dates</th><th>Tournament</th></tr></thead><tbody>")
        for t in tournaments {
            var dates = dayFormatter.string(from: t.start)
            if ICS.utcDay(t.start) != ICS.utcDay(t.end) {
                dates += " – " + dayFormatter.string(from: t.end)
            }
            b.add("<tr><td>" + WebEscape.html(dates) + "</td><td>" + WebEscape.html(t.name) + "</td></tr>")
        }
        b.add("</tbody></table></section>")
        return b.html
    }

    // MARK: - JSON-LD

    static func eventsJSONLD(_ games: [Game], site: PublicSite) -> String {
        var items: [[String: Any]] = []
        for game in games {
            if let item = sportsEvent(game, site: site) { items.append(item) }
        }
        if items.isEmpty { return "" }
        let root: Any = items.count == 1 ? items[0] : items
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else { return "" }
        return WebEscape.scriptJSON(String(decoding: data, as: UTF8.self))
    }

    static func sportsEvent(_ game: Game, site: PublicSite) -> [String: Any]? {
        guard let start = PublicGame.start(game), let id = game.idEvent else { return nil }
        var item: [String: Any] = [:]
        item["@context"] = "https://schema.org"
        item["@type"] = "SportsEvent"
        item["name"] = PublicGame.title(game)
        item["startDate"] = isoFormatter.string(from: start)
        item["endDate"] = isoFormatter.string(from: PublicGame.endDate(game) ?? start.addingTimeInterval(PublicGame.duration(game)))
        item["url"] = site.absolute(site.gamePath(id))
        item["eventAttendanceMode"] = "https://schema.org/OfflineEventAttendanceMode"
        switch ScheduleCalendarVersion.state(of: game) {
        case .calledOff(let label):
            let lowered = label.lowercased()
            item["eventStatus"] = lowered.contains("cancel") || lowered.contains("canc") ? "https://schema.org/EventCancelled" : "https://schema.org/EventPostponed"
        default:
            item["eventStatus"] = "https://schema.org/EventScheduled"
        }
        if let league = game.strLeague { item["sport"] = league }
        var place: [String: Any] = ["@type": "Place"]
        place["name"] = game.venueName ?? (game.strLeague ?? "TBD")
        item["location"] = place
        if !game.isIndividualSport {
            item["homeTeam"] = ["@type": "SportsTeam", "name": game.strHomeTeam]
            item["awayTeam"] = ["@type": "SportsTeam", "name": game.strAwayTeam]
            item["competitor"] = [
                ["@type": "SportsTeam", "name": game.strHomeTeam],
                ["@type": "SportsTeam", "name": game.strAwayTeam],
            ]
        }
        return item
    }

    // MARK: - Page shell

    static func page(title: String, description: String, canonical: String, appArgument: String, jsonLD: String, body: String, site: PublicSite) -> String {
        var b = HTMLBuilder()
        b.add("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">")
        b.add("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
        b.add("<title>" + WebEscape.html(title) + " | " + PublicSite.brand + "</title>")
        b.add("<meta name=\"description\" content=\"" + WebEscape.html(description) + "\">")
        b.add("<link rel=\"canonical\" href=\"" + WebEscape.html(canonical) + "\">")
        b.add("<meta name=\"apple-itunes-app\" content=\"app-id=" + PublicSite.appStoreID + ", app-argument=" + WebEscape.html(appArgument) + "\">")
        b.add("<meta name=\"color-scheme\" content=\"light dark\">")
        b.add("<meta property=\"og:type\" content=\"website\">")
        b.add("<meta property=\"og:site_name\" content=\"" + PublicSite.brand + "\">")
        b.add("<meta property=\"og:title\" content=\"" + WebEscape.html(title) + "\">")
        b.add("<meta property=\"og:description\" content=\"" + WebEscape.html(description) + "\">")
        b.add("<meta property=\"og:url\" content=\"" + WebEscape.html(canonical) + "\">")
        b.add("<style>" + css + "</style>")
        if !jsonLD.isEmpty {
            b.add("<script type=\"application/ld+json\">" + jsonLD + "</script>")
        }
        b.add("</head><body><header><a class=\"brand\" href=\"" + PublicSite.appStoreURL + "\">" + PublicSite.brand + "</a></header><main>")
        b.add(body)
        b.add("</main><footer><p class=\"muted small\">Times shown in your local time zone where supported, otherwise UTC. Schedules change; check the app for the latest.</p></footer>")
        b.add("<script>" + localTimeScript + "</script>")
        b.add("</body></html>")
        return b.html
    }

    static let css = """
    :root{--bg:#ffffff;--fg:#14161a;--muted:#5f6673;--line:#e3e6eb;--card:#f5f7fa;--accent:#0a64d8;--accent-fg:#ffffff;--live:#d6293e}
    @media (prefers-color-scheme:dark){:root{--bg:#0f1115;--fg:#eceef2;--muted:#9aa2ae;--line:#262a31;--card:#171a20;--accent:#4c93ff;--accent-fg:#0f1115;--live:#ff5c6c}}
    *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
    header,main,footer{max-width:760px;margin:0 auto;padding:0 16px}header{padding-top:16px}
    .brand{font-weight:700;color:var(--fg);text-decoration:none}
    h1{font-size:1.6rem;line-height:1.25;margin:.4em 0}h2{font-size:1.15rem;margin:1.6em 0 .5em}
    a{color:var(--accent)}.muted{color:var(--muted)}.small{font-size:.85rem}.crumb{margin:.8em 0 0;font-size:.9rem}
    table{width:100%;border-collapse:collapse;font-size:.95rem}th,td{text-align:left;padding:8px 6px;border-bottom:1px solid var(--line);vertical-align:top}
    th{font-size:.8rem;color:var(--muted);font-weight:600;text-transform:uppercase;letter-spacing:.03em}td:first-child{white-space:nowrap;color:var(--muted)}
    .actions{display:flex;flex-wrap:wrap;gap:8px;margin:12px 0 4px}
    .btn{display:inline-block;padding:9px 14px;border-radius:10px;border:1px solid var(--line);background:var(--card);color:var(--fg);text-decoration:none;font-weight:600;font-size:.95rem}
    .btn.primary{background:var(--accent);border-color:var(--accent);color:var(--accent-fg)}
    .card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:12px 16px;margin:12px 0}
    .card p{margin:.3em 0}.when{font-weight:600}.score{font-size:1.3rem;font-weight:700}
    .badge{display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid var(--line);font-size:.8rem;font-weight:600}.badge.live{color:var(--live);border-color:var(--live)}
    .teams{columns:2;padding-left:18px}@media (max-width:480px){.teams{columns:1}td{padding:8px 4px}}
    .cta{margin:28px 0;padding:16px;border-radius:14px;background:var(--card);border:1px solid var(--line)}.cta h2{margin-top:0}
    footer{padding-bottom:32px}
    """

    static let localTimeScript = """
    (function(){var o={s:{weekday:'short',month:'short',day:'numeric',hour:'numeric',minute:'2-digit'},l:{weekday:'long',month:'long',day:'numeric',year:'numeric',hour:'numeric',minute:'2-digit',timeZoneName:'short'},d:{weekday:'short',month:'short',day:'numeric',timeZone:'UTC'}};document.querySelectorAll('time[data-t]').forEach(function(e){var d=new Date(e.getAttribute('datetime'));var f=o[e.getAttribute('data-t')];if(!isNaN(d)&&f){try{e.textContent=d.toLocaleString([],f)}catch(x){}}})})();
    """

    // MARK: - Formatting

    static func yearLabel(_ now: Date) -> String {
        String(Calendar(identifier: .gregorian).component(.year, from: now))
    }

    static func longDate(_ date: Date) -> String {
        dayLongFormatter.string(from: date)
    }

    static func dayAfter(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: day) ?? date.addingTimeInterval(86_400)
    }

    private static func utcFormatter(_ format: String) -> DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = format
        return df
    }

    nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    nonisolated(unsafe) static let shortFormatter = utcFormatter("EEE, MMM d · HH:mm")
    nonisolated(unsafe) static let longFormatter = utcFormatter("EEEE, MMMM d, yyyy · HH:mm")
    nonisolated(unsafe) static let dayFormatter = utcFormatter("EEE, MMM d")
    nonisolated(unsafe) static let dayLongFormatter = utcFormatter("MMM d, yyyy")
}

/// Accumulates markup one piece at a time (see the type-checking note at the top).
struct HTMLBuilder {
    private(set) var html = ""

    mutating func add(_ piece: String) {
        html += piece
    }
}
