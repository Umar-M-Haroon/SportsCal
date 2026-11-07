//
//  WebEscape.swift
//
//  Output escaping for the public, server-rendered pages. Everything these pages show
//  comes from upstream feeds (team names, venues, tournament names), so every value is
//  escaped at the point it enters markup. The admin dashboard once had an XSS from
//  exactly that kind of upstream string, so there is no "trusted" path here.
//

import Foundation

enum WebEscape {
    /// Escapes text for HTML element content *and* quoted attribute values.
    static func html(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    /// Makes encoded JSON safe to embed in a `<script type="application/ld+json">` block:
    /// `<`, `>` and `&` become `<` etc. so a value containing `</script>` cannot
    /// close the block. The result is still valid JSON with the same meaning.
    static func scriptJSON(_ json: String) -> String {
        var out = ""
        out.reserveCapacity(json.utf8.count)
        for ch in json.unicodeScalars {
            switch ch {
            case "<": out += "\\u003c"
            case ">": out += "\\u003e"
            case "&": out += "\\u0026"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    /// A URL-safe slug ("Paris Saint-Germain" → "paris-saint-germain"). Accents are
    /// folded to ASCII; anything else outside `[a-z0-9]` becomes a single hyphen.
    static func slug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var out = ""
        var lastWasHyphen = true
        for ch in folded.lowercased().unicodeScalars {
            let isAlnum = (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9")
            if isAlnum {
                out.unicodeScalars.append(ch)
                lastWasHyphen = false
            } else if !lastWasHyphen {
                out += "-"
                lastWasHyphen = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return String(out.prefix(80))
    }

    /// Whether a path ID is safe to use: 1–40 of `[A-Za-z0-9_-]`. Team, league and event
    /// IDs are all of this shape (TheSportsDB numbers, `ncaaf-145`, `indycar-2201035`).
    static func isSafeID(_ s: String) -> Bool {
        guard !s.isEmpty, s.utf8.count <= 40 else { return false }
        for b in s.utf8 {
            let ok = (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x2D || b == 0x5F
            if !ok { return false }
        }
        return true
    }
}
