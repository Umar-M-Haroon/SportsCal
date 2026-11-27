//
//  PublicHome.swift
//
//  The marketing homepage (`/`) and the press kit (`/press`). Everything that links to
//  the app from outside the App Store (posts, press, QR codes, the team pages' header)
//  lands here, so it has to explain the app in one screen and get to the App Store
//  button fast.
//
//  Same rules as PublicPages.swift: upstream strings (league names) go through
//  `WebEscape.html`, and markup is built one short statement at a time because the
//  Linux release compiler has failed the prod build on long `+` chains.
//
//  Static images live in `Public/site/` and are served by FileMiddleware.
//  No odds, lines or betting content, by product decision.
//

import Foundation
import SportsCalModel

enum PublicHome {
    static let macAppStoreURL = PublicSite.appStoreURL + "?platform=mac"
    static let supportEmail = "support@komodollc.com"
    static let privacyURL = "https://komodollc.com/privacy"
    static let leagueLimit = 30

    struct Feature {
        let title: String
        let text: String
        let pro: Bool
    }

    static let features: [Feature] = [
        Feature(title: "Live on your Lock Screen",
                text: "Live Activities and the Dynamic Island for every sport, including golf, tennis, F1 and cricket. Scores update within seconds.",
                pro: false),
        Feature(title: "Every game on one calendar",
                text: "A colour-coded calendar of every game you care about, plus subscribable team calendars for Apple and Google Calendar.",
                pro: false),
        Feature(title: "Alerts you set up",
                text: "Get told when a player hits a milestone, every time your team scores, or when a game gets close late.",
                pro: true),
        Feature(title: "Every match, in depth",
                text: "A soccer match centre for every league: lineups on the pitch, shot maps, momentum, commentary, form and head-to-head.",
                pro: false),
        Feature(title: "Every lap of every race",
                text: "F1 gap and lap charts, tyres, weather and safety cars, plus NASCAR, IndyCar, IMSA and WEC.",
                pro: false),
        Feature(title: "Widgets, Watch and Mac",
                text: "Home Screen and Lock Screen widgets, Apple Watch complications, and a native Mac app. Make it yours with themes.",
                pro: false),
    ]

    static let sportsLine = "NFL · NBA · WNBA · MLB · NHL · college football and basketball · Premier League, Champions League, MLS and 20+ soccer leagues · F1 · NASCAR · IndyCar · tennis · golf · cricket"

    static let shots: [(file: String, alt: String)] = [
        ("shot-2.jpg", "A live game on the iPhone Lock Screen as a Live Activity"),
        ("shot-1.jpg", "The live scores feed"),
        ("shot-3.jpg", "Soccer lineups on the pitch"),
        ("shot-4.jpg", "Live win probability and box score"),
        ("shot-5.jpg", "F1 gap chart and lap chart"),
        ("shot-6.jpg", "A team's whole season, preseason to playoffs"),
        ("shot-7.jpg", "College football CFP, AP and Coaches rankings"),
        ("shot-8.jpg", "Browse every sport"),
    ]

    // MARK: - Home

    static func homePage(schedule: PublicSchedule, site: PublicSite) -> String {
        let title = "Scoreline — Live Sports Scores, Schedules & Alerts"
        let description = "Live scores on your Lock Screen and every game on one calendar. NFL, NBA, MLB, NHL, college, soccer, F1 and more for iPhone, iPad, Apple Watch and Mac. No betting. No odds."

        var b = HTMLBuilder()
        b.add("<section class=\"hero\">")
        b.add("<img class=\"icon\" src=\"/site/icon-256.png\" width=\"112\" height=\"112\" alt=\"Scoreline app icon\">")
        b.add("<h1>Live scores on your Lock Screen.<br>Every game on one calendar.</h1>")
        b.add("<p class=\"lede\">Scoreline follows your teams across every sport, with Live Activities, widgets and alerts that tell you when it matters.</p>")
        b.add(storeButtons())
        b.add("<p class=\"muted small\">Free on iPhone, iPad, Apple Watch and Mac. <strong>No betting. No odds.</strong></p>")
        b.add("</section>")

        b.add("<section class=\"shots\" aria-label=\"Screenshots\"><div class=\"strip\">")
        for shot in shots {
            b.add("<img src=\"/site/" + shot.file + "\" width=\"270\" height=\"587\" loading=\"lazy\" alt=\"")
            b.add(WebEscape.html(shot.alt) + "\">")
        }
        b.add("</div></section>")

        b.add("<section><h2>What it does</h2><div class=\"grid\">")
        for feature in features {
            b.add("<div class=\"tile\"><h3>" + WebEscape.html(feature.title))
            if feature.pro { b.add(" <span class=\"pro\">Pro</span>") }
            b.add("</h3><p>" + WebEscape.html(feature.text) + "</p></div>")
        }
        b.add("</div></section>")

        b.add("<section><h2>Every sport, one app</h2>")
        b.add("<p>" + WebEscape.html(sportsLine) + ".</p></section>")

        b.add("<section><h2>Scoreline Pro</h2>")
        b.add("<p>The app is free. Pro adds alerts for any game, pre-game reminders, custom player and game alerts, themes and no ads. Pay monthly, yearly or once for Lifetime; prices are shown in the app.</p>")
        b.add("</section>")

        b.add(leagueSection(schedule: schedule, site: site))

        b.add("<aside class=\"cta\"><h2>Get Scoreline</h2>")
        b.add(storeButtons())
        b.add("</aside>")

        return shell(title: title, description: description, canonical: site.absolute("/"), body: b.html, site: site)
    }

    /// The leagues most people search for, listed first in this order when they have
    /// games in the window. The rest fill in by game count, so the list isn't led by
    /// whichever cricket league happens to play the most fixtures.
    static let featuredLeagueIDs = [
        "4391", "102", "4387", "100", "4424", "4380", "101",          // NFL, CFB, NBA, CBB, MLB, NHL, WNBA
        "4328", "4480", "4346", "4335", "4332", "4331", "4334",       // EPL, UCL, MLS, La Liga, Serie A, Bundesliga, Ligue 1
        "4350", "4370", "4393", "4373", "4425", "4464", "4517",       // Liga MX, F1, NASCAR, IndyCar, PGA, ATP, WTA
    ]

    /// Links into the SEO schedule pages, so the homepage is also the hub crawlers reach
    /// them from.
    static func leagueSection(schedule: PublicSchedule, site: PublicSite) -> String {
        let leagues = homeLeagues(schedule)
        if leagues.isEmpty { return "" }
        var b = HTMLBuilder()
        b.add("<section><h2>Schedules you can add to your calendar</h2><ul class=\"pills\">")
        for league in leagues {
            b.add("<li><a href=\"" + WebEscape.html(site.leaguePath(league)) + "\">")
            b.add(WebEscape.html(league.name) + "</a></li>")
        }
        b.add("</ul></section>")
        return b.html
    }

    static func homeLeagues(_ schedule: PublicSchedule) -> [PublicLeague] {
        var picked: [PublicLeague] = []
        var seen = Set<String>()
        for id in featuredLeagueIDs {
            guard let league = schedule.leagues[id], !league.games.isEmpty else { continue }
            picked.append(league)
            seen.insert(id)
        }
        let rest = schedule.leagues.values
            .filter { !seen.contains($0.id) && !$0.games.isEmpty }
            .sorted { lhs, rhs in
                if lhs.games.count != rhs.games.count { return lhs.games.count > rhs.games.count }
                return lhs.name < rhs.name
            }
        for league in rest where picked.count < leagueLimit {
            picked.append(league)
        }
        return picked
    }

    static func storeButtons() -> String {
        var b = HTMLBuilder()
        b.add("<div class=\"actions\">")
        b.add("<a class=\"btn primary\" href=\"" + PublicSite.appStoreURL + "\">Download on the App Store</a>")
        b.add("<a class=\"btn\" href=\"" + macAppStoreURL + "\">Get it for Mac</a>")
        b.add("</div>")
        return b.html
    }

    // MARK: - Press

    static func pressPage(site: PublicSite) -> String {
        let title = "Press kit — Scoreline"
        let description = "Press kit for Scoreline: app description, fact sheet, icon and screenshots."

        var b = HTMLBuilder()
        b.add("<h1>Press kit</h1>")
        b.add("<p class=\"lede\">Everything you need to write about Scoreline. For review access to Pro, interviews or anything else, email ")
        b.add("<a href=\"mailto:" + supportEmail + "\">" + supportEmail + "</a>.</p>")

        b.add("<section><h2>In one line</h2>")
        b.add("<p>Scoreline is a sports app for iPhone, iPad, Apple Watch and Mac that puts live scores on your Lock Screen and every game on one calendar, with no betting and no odds.</p></section>")

        b.add("<section><h2>Description</h2>")
        b.add("<p>Scoreline covers the NFL, NBA, WNBA, MLB, NHL, college football and basketball, more than 20 soccer leagues, F1, NASCAR, IndyCar, tennis, golf and cricket. Live Activities and the Dynamic Island work for every sport, including golf leaderboards, tennis matches and F1 sessions.</p>")
        b.add("<p>Beyond scores, it is built for planning: a calendar of every game you follow, team pages with the whole season, and subscribable calendars for Apple and Google Calendar. For fans who want depth, there is a soccer match centre (lineups, shot maps, momentum), F1 lap and gap charts, live win probability and college rankings.</p>")
        b.add("<p>Scoreline Pro adds custom alerts (a player's milestone, every score, a close finish), pre-game reminders, themes and no ads. Unlike most sports apps in 2026, Scoreline carries no betting lines, odds or sportsbook promotions.</p>")
        b.add("</section>")

        b.add("<section><h2>Fact sheet</h2><table><tbody>")
        b.add(factRow("Name", "Scoreline: Live Sports Scores"))
        b.add(factRow("Developer", "Mighty Panda LLC (independent)"))
        b.add(factRow("Platforms", "iPhone, iPad, Apple Watch, Mac"))
        b.add(factRow("Price", "Free, with optional Scoreline Pro (monthly, yearly or Lifetime)"))
        b.add(factRow("Sports", sportsLine))
        b.add("<tr><th>App Store</th><td><a href=\"" + PublicSite.appStoreURL + "\">" + PublicSite.appStoreURL + "</a></td></tr>")
        b.add("<tr><th>Contact</th><td><a href=\"mailto:" + supportEmail + "\">" + supportEmail + "</a></td></tr>")
        b.add("</tbody></table></section>")

        b.add("<section><h2>Logo and images</h2><ul>")
        b.add("<li><a href=\"/site/icon-1024.png\">App icon, 1024 × 1024 PNG</a></li>")
        b.add("<li><a href=\"/site/og.jpg\">Banner, 1200 × 630 JPEG</a></li>")
        b.add("</ul><div class=\"strip\">")
        for shot in shots {
            b.add("<a href=\"/site/" + shot.file + "\"><img src=\"/site/" + shot.file + "\" width=\"180\" height=\"391\" loading=\"lazy\" alt=\"")
            b.add(WebEscape.html(shot.alt) + "\"></a>")
        }
        b.add("</div><p class=\"muted small\">Full-resolution screenshots on request.</p></section>")

        return shell(title: title, description: description, canonical: site.absolute("/press"), body: b.html, site: site)
    }

    static func factRow(_ label: String, _ value: String) -> String {
        "<tr><th>" + WebEscape.html(label) + "</th><td>" + WebEscape.html(value) + "</td></tr>"
    }

    // MARK: - Shell

    static func shell(title: String, description: String, canonical: String, body: String, site: PublicSite) -> String {
        let image = site.absolute("/site/og.jpg")
        var b = HTMLBuilder()
        b.add("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">")
        b.add("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
        b.add("<title>" + WebEscape.html(title) + "</title>")
        b.add("<meta name=\"description\" content=\"" + WebEscape.html(description) + "\">")
        b.add("<link rel=\"canonical\" href=\"" + WebEscape.html(canonical) + "\">")
        b.add("<link rel=\"icon\" type=\"image/png\" href=\"/site/icon-256.png\">")
        b.add("<link rel=\"apple-touch-icon\" href=\"/site/apple-touch-icon.png\">")
        b.add("<meta name=\"apple-itunes-app\" content=\"app-id=" + PublicSite.appStoreID + "\">")
        b.add("<meta name=\"color-scheme\" content=\"light dark\">")
        b.add("<meta property=\"og:type\" content=\"website\">")
        b.add("<meta property=\"og:site_name\" content=\"" + PublicSite.brand + "\">")
        b.add("<meta property=\"og:title\" content=\"" + WebEscape.html(title) + "\">")
        b.add("<meta property=\"og:description\" content=\"" + WebEscape.html(description) + "\">")
        b.add("<meta property=\"og:url\" content=\"" + WebEscape.html(canonical) + "\">")
        b.add("<meta property=\"og:image\" content=\"" + WebEscape.html(image) + "\">")
        b.add("<meta name=\"twitter:card\" content=\"summary_large_image\">")
        b.add("<style>" + PublicPages.css + css + "</style>")
        b.add("<script type=\"application/ld+json\">" + appJSONLD(description: description, site: site) + "</script>")
        b.add("</head><body><header><a class=\"brand\" href=\"/\">" + PublicSite.brand + "</a>")
        b.add("<nav><a href=\"/press\">Press</a></nav></header><main>")
        b.add(body)
        b.add("</main><footer><p class=\"muted small\">© Mighty Panda LLC · ")
        b.add("<a href=\"/press\">Press</a> · ")
        b.add("<a href=\"" + privacyURL + "\">Privacy</a> · ")
        b.add("<a href=\"mailto:" + supportEmail + "\">Contact</a></p></footer>")
        b.add("</body></html>")
        return b.html
    }

    static func appJSONLD(description: String, site: PublicSite) -> String {
        var item: [String: Any] = [:]
        item["@context"] = "https://schema.org"
        item["@type"] = "MobileApplication"
        item["name"] = "Scoreline: Live Sports Scores"
        item["operatingSystem"] = "iOS, iPadOS, watchOS, macOS"
        item["applicationCategory"] = "SportsApplication"
        item["description"] = description
        item["url"] = site.absolute("/")
        item["image"] = site.absolute("/site/icon-1024.png")
        item["installUrl"] = PublicSite.appStoreURL
        item["offers"] = ["@type": "Offer", "price": "0", "priceCurrency": "USD"]
        guard let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]) else { return "{}" }
        return WebEscape.scriptJSON(String(decoding: data, as: UTF8.self))
    }

    static let css = """
    header{display:flex;justify-content:space-between;align-items:center}header nav a{color:var(--muted);text-decoration:none;font-size:.95rem}
    .hero{text-align:center;padding:28px 0 8px}.hero .icon{border-radius:24px;box-shadow:0 6px 24px rgba(0,0,0,.18)}
    .hero h1{font-size:2rem;overflow-wrap:break-word;line-height:1.2;margin:.5em 0 .3em}.lede{font-size:1.1rem;color:var(--muted);max-width:640px;margin:0 0 8px}.hero .lede{max-width:560px;margin:0 auto 8px}
    .hero .actions{justify-content:center;margin:18px 0 10px}
    .strip{display:flex;gap:12px;overflow-x:auto;scroll-snap-type:x mandatory;padding:8px 2px 14px;-webkit-overflow-scrolling:touch}
    .strip img{flex:0 0 auto;height:auto;border-radius:16px;scroll-snap-align:start;border:1px solid var(--line)}
    .shots .strip img{width:220px}.strip a img{width:150px}
    .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(220px,100%),1fr));gap:12px}
    .tile{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px 16px}.tile h3{margin:0 0 6px;font-size:1rem}.tile p{margin:0;color:var(--muted);font-size:.95rem}
    .pro{font-size:.7rem;font-weight:700;padding:1px 6px;border-radius:999px;background:var(--accent);color:var(--accent-fg);vertical-align:2px}
    .pills{list-style:none;padding:0;display:flex;flex-wrap:wrap;gap:8px}.pills a{display:inline-block;padding:5px 11px;border-radius:999px;border:1px solid var(--line);background:var(--card);text-decoration:none;font-size:.9rem;color:var(--fg)}
    th{text-transform:none;letter-spacing:0;font-size:.9rem;white-space:nowrap;padding-right:14px}td:first-child{white-space:normal;color:var(--fg)}
    @media (max-width:480px){.hero h1{font-size:1.55rem}.shots .strip img{width:180px}}
    """
}
