//
//  DeepLink.swift
//  SportsCal
//
//  Universal-link parsing/building for shareable game + World Cup bracket links.
//  Pure (no app/view state) so it's unit-testable. The shareable URL resolves to
//  the server's web fallback (App Store smart banner) for recipients without the
//  app, and opens the app directly once Associated Domains + the apple-app-site-
//  association are live.
//

import Foundation

/// A route an inbound universal link can open.
enum DeepLinkRoute: Equatable {
    case game(idEvent: String)
    case worldCupBracket
}

enum DeepLink {
    /// The universal-link host. Must match the `applinks:<host>` Associated
    /// Domains entitlement and the apple-app-site-association served by the
    /// server. TODO(domain): confirm the production host and point its DNS at the
    /// Vapor server before enabling the entitlement.
    static let host = "sportscal.app"

    /// Build the shareable link for a route.
    static func url(for route: DeepLinkRoute) -> URL? {
        switch route {
        case .game(let id):
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            return URL(string: "https://\(host)/g/\(encoded)")
        case .worldCupBracket:
            return URL(string: "https://\(host)/wc/bracket")
        }
    }

    /// The public web schedule page for a team (server: `/team/:id`, which
    /// redirects to the slugged URL). Only TheSportsDB numeric team ids exist there.
    static func teamPageURL(teamID: String) -> URL? {
        guard isServerTeamID(teamID) else { return nil }
        return URL(string: "https://\(host)/team/\(teamID)")
    }

    /// A subscribable calendar feed of the team's games (server: `/cal/team/:id.ics`).
    /// `webcal://` hands it to Calendar as a subscription that keeps itself updated,
    /// rather than a one-off import.
    static func teamCalendarURL(teamID: String) -> URL? {
        guard isServerTeamID(teamID) else { return nil }
        return URL(string: "webcal://\(host)/cal/team/\(teamID).ics")
    }

    static func isServerTeamID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 12 && id.allSatisfy(\.isASCIIDigit)
    }

    /// Parse an inbound link into a route, or nil if it isn't one of ours. Host is
    /// not checked — the OS only delivers links for our associated domain, so this
    /// also tolerates staging/alternate hosts.
    static func parse(_ url: URL) -> DeepLinkRoute? {
        let parts = url.pathComponents.filter { $0 != "/" }
        switch parts.first {
        case "g":
            guard parts.count >= 2, !parts[1].isEmpty else { return nil }
            return .game(idEvent: parts[1])
        case "wc":
            guard parts.count >= 2, parts[1] == "bracket" else { return nil }
            return .worldCupBracket
        default:
            return nil
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
