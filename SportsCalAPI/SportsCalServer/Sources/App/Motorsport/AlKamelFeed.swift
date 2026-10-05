//
//  AlKamelFeed.swift
//
//  Result files from Al Kamel Systems' public results sites, the official timing
//  provider of IMSA (imsa.results.alkamelcloud.com, JSON) and the FIA WEC
//  (fiawec.alkamelsystems.com, CSV only). Both lay results out as
//  `Results/{NN_season}/{NN_event}/{NN_championship}/{yyyyMMddHHmm_Session}/…`, with
//  endurance races published hour by hour (`…_Race/01_Hour 1/`). Only the public
//  results files are used, never Al Kamel's live-timing service.
//
//  File names are inconsistent (double spaces, "Final" misspelt into the extension),
//  so links are always scraped from the listing, never built.
//

import Foundation
import SportsCalModel

/// One car's line in a session, normalised across the IMSA JSON and WEC CSV formats.
struct AlKamelEntry: Codable, Equatable {
    var position: Int
    var number: String
    var team: String?
    var vehicleClass: String?
    var vehicle: String?
    var manufacturer: String?
    var drivers: [String]
    var laps: Int?
    /// Race: total elapsed time. Practice/qualifying: best lap.
    var time: String?
    var gapFirst: String?
    var bestLap: String?
    var pitStops: Int?
    var retired: Bool
}

/// A session as parsed from its result file.
struct AlKamelSession: Codable, Equatable {
    /// The folder name ("202610031210_Race"), unique within an event.
    var folder: String
    var name: String
    /// `EventSession.sessionType`: practice, qual or race.
    var type: String
    /// Local track time from the folder name.
    var localStart: Date?
    var entries: [AlKamelEntry]
    /// The race's latest published hour, while it runs (endurance).
    var hour: Int?
    /// Whether the results are the final version (Provisional/Official, WEC "Final").
    var isFinal: Bool
    /// Race length in seconds (IMSA states it; WEC's comes from the race name).
    var duration: Double?
}

enum AlKamelParse {
    // MARK: Listings

    /// `href`s in an HTML page or Apache directory listing, decoded, without query links.
    static func links(in html: String) -> [String] {
        let pattern = #"href="([^"?][^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            Range(match.range(at: 1), in: html).map { String(html[$0]) }
        }
    }

    /// `<option Value="…">` values of a named `<select>` (WEC's season/event pickers).
    static func options(named name: String, in html: String) -> [String] {
        guard let start = html.range(of: "name=\"\(name)\""),
              let end = html.range(of: "</select>", range: start.upperBound..<html.endIndex) else { return [] }
        let block = String(html[start.upperBound..<end.lowerBound])
        guard let regex = try? NSRegularExpression(pattern: #"[Vv]alue="([^"]+)""#) else { return [] }
        return regex.matches(in: block, range: NSRange(block.startIndex..., in: block)).compactMap { match in
            Range(match.range(at: 1), in: block).map { String(block[$0]) }
        }
    }

    /// "202610031210_Race" → (local start, "Race").
    static func sessionFolder(_ folder: String) -> (start: Date?, name: String)? {
        let parts = folder.split(separator: "_", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 12, parts[0].allSatisfy(\.isNumber) else { return nil }
        return (folderFormatter.date(from: String(parts[0])), String(parts[1]).trimmingCharacters(in: .whitespaces))
    }

    /// Session name → `EventSession.sessionType`; nil for sessions that aren't part of a
    /// race weekend's story (test days, starting grids).
    static func sessionType(_ name: String) -> String? {
        let lowered = name.lowercased()
        if lowered.contains("test") || lowered.contains("prologue") { return nil }
        if lowered.hasPrefix("race") { return "race" }
        if lowered.contains("qualif") || lowered.contains("hyperpole") { return "qual" }
        if lowered.contains("practice") || lowered.contains("warm") || lowered.hasPrefix("session") { return "practice" }
        return nil
    }

    /// Prefer the most final version of a result: Official > Provisional > Final > Unofficial.
    static func markRank(_ file: String) -> Int {
        let lowered = file.lowercased()
        if lowered.contains("official") && !lowered.contains("unofficial") { return 4 }
        if lowered.contains("provisional") { return 3 }
        if lowered.contains("final") { return 2 }
        if lowered.contains("unofficial") { return 1 }
        return 0
    }

    static func isFinalMark(_ file: String) -> Bool { markRank(file) >= 2 }

    // MARK: IMSA JSON

    struct IMSAResults: Decodable {
        let session: Session?
        let classifications: [Class]?
        let classification: [Row]?

        struct Session: Decodable {
            let finalizeType: Finalize?
            enum CodingKeys: String, CodingKey { case finalizeType = "finalize_type" }
            struct Finalize: Decodable {
                let type: String?
                let timeInSeconds: Double?
                enum CodingKeys: String, CodingKey { case type; case timeInSeconds = "time_in_seconds" }
            }
        }
        struct Class: Decodable { let name: String; let classification: [Row] }
        struct Row: Decodable {
            let status: String?
            let notFinished: Bool
            let position: Int
            let number: String
            let laps: String?
            let elapsedTime: String?
            let time: String?
            let gapFirst: String?
            let pitStops: String?
            let fastestLapTime: String?
            let team: String?
            let cls: String?
            let vehicle: String?
            let manufacturer: String?
            let drivers: [Driver]?

            struct Driver: Decodable { let firstname: String?; let surname: String? }

            enum CodingKeys: String, CodingKey {
                case status, position, number, laps, time, team, vehicle, manufacturer, drivers
                case notFinished = "not_finished"
                case elapsedTime = "elapsed_time"
                case gapFirst = "gap_first"
                case pitStops = "pit_stops"
                case fastestLapTime = "fastest_lap_time"
                case cls = "class"
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                status = try? c.decode(String.self, forKey: .status)
                // `not_finished` is a bool in some files and the string "False" in others.
                if let flag = try? c.decode(Bool.self, forKey: .notFinished) {
                    notFinished = flag
                } else {
                    notFinished = ((try? c.decode(String.self, forKey: .notFinished)) ?? "").lowercased() == "true"
                }
                position = (try? c.decode(Int.self, forKey: .position)) ?? Int((try? c.decode(String.self, forKey: .position)) ?? "") ?? 0
                number = (try? c.decode(String.self, forKey: .number)) ?? ((try? c.decode(Int.self, forKey: .number)).map(String.init) ?? "")
                laps = try? c.decode(String.self, forKey: .laps)
                elapsedTime = try? c.decode(String.self, forKey: .elapsedTime)
                time = try? c.decode(String.self, forKey: .time)
                gapFirst = try? c.decode(String.self, forKey: .gapFirst)
                pitStops = try? c.decode(String.self, forKey: .pitStops)
                fastestLapTime = try? c.decode(String.self, forKey: .fastestLapTime)
                team = try? c.decode(String.self, forKey: .team)
                cls = try? c.decode(String.self, forKey: .cls)
                vehicle = try? c.decode(String.self, forKey: .vehicle)
                manufacturer = try? c.decode(String.self, forKey: .manufacturer)
                drivers = try? c.decode([Driver].self, forKey: .drivers)
            }
        }
    }

    /// IMSA results (overall or by class) → entries in overall order. A by-class file is
    /// flattened and re-ordered by laps and time, since its positions are per class.
    static func imsaEntries(_ data: Data, isRace: Bool) throws -> (entries: [AlKamelEntry], duration: Double?) {
        let results = try JSONDecoder().decode(IMSAResults.self, from: stripBOM(data))
        var rows: [IMSAResults.Row] = results.classification ?? []
        if rows.isEmpty {
            rows = (results.classifications ?? []).flatMap(\.classification)
            rows.sort { lhs, rhs in
                if isRace {
                    let (l, r) = (Int(lhs.laps ?? "") ?? 0, Int(rhs.laps ?? "") ?? 0)
                    if l != r { return l > r }
                    return seconds(lhs.elapsedTime) < seconds(rhs.elapsedTime)
                }
                return seconds(lhs.time ?? lhs.fastestLapTime) < seconds(rhs.time ?? rhs.fastestLapTime)
            }
        }
        let entries = rows.enumerated().map { index, row in
            AlKamelEntry(
                position: results.classification == nil ? index + 1 : row.position,
                number: row.number,
                team: nonEmpty(row.team), vehicleClass: nonEmpty(row.cls), vehicle: nonEmpty(row.vehicle),
                manufacturer: nonEmpty(row.manufacturer),
                drivers: (row.drivers ?? []).map { [$0.firstname, $0.surname].compactMap { $0 }.joined(separator: " ") },
                laps: Int(row.laps ?? ""),
                time: nonEmpty(isRace ? row.elapsedTime : (row.time ?? row.fastestLapTime)),
                gapFirst: nonEmpty(row.gapFirst).flatMap { $0 == "-" ? nil : $0 },
                bestLap: nonEmpty(row.fastestLapTime ?? row.time),
                pitStops: Int(row.pitStops ?? ""),
                retired: row.notFinished || (row.status ?? "").lowercased().contains("retire")
            )
        }
        let duration = results.session?.finalizeType?.type?.lowercased().contains("time") == true
            ? results.session?.finalizeType?.timeInSeconds : nil
        return (entries, duration)
    }

    // MARK: WEC CSV

    /// WEC classification CSV (`;`-separated, BOM): race and practice share one layout
    /// (DRIVER_1…5), qualifying and Hyperpole another (DRIVERn_FIRSTNAME/SECONDNAME).
    static func wecEntries(_ data: Data, isRace: Bool) -> [AlKamelEntry] {
        let text = String(decoding: stripBOM(data), as: UTF8.self)
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return [] }
        let header = lines.removeFirst().split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        func column(_ names: String...) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }
        let pos = column("POSITION", "POS"), num = column("NUMBER"), team = column("TEAM"), cls = column("CLASS")
        let vehicle = column("VEHICLE"), status = column("STATUS"), laps = column("LAPS")
        let total = column("TOTAL_TIME"), time = column("TIME"), gap = column("GAP_FIRST"), fl = column("FL_TIME")
        let driverColumns = header.indices.filter { header[$0].range(of: #"^DRIVER_\d$"#, options: .regularExpression) != nil }
        let firstNames = header.indices.filter { header[$0].range(of: #"^DRIVER\d_FIRSTNAME$"#, options: .regularExpression) != nil }

        return lines.compactMap { line in
            let f = line.split(separator: ";", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            func value(_ index: Int?) -> String? { index.flatMap { $0 < f.count ? nonEmpty(f[$0]) : nil } }
            guard let position = value(pos).flatMap(Int.init), let number = value(num) else { return nil }
            var drivers = driverColumns.compactMap { value($0) }
            if drivers.isEmpty {
                drivers = firstNames.compactMap { first in
                    let last = first + 1
                    return [value(first), value(last)].compactMap { $0 }.joined(separator: " ").nilIfEmpty
                }
            }
            return AlKamelEntry(
                position: position, number: number, team: value(team), vehicleClass: value(cls),
                vehicle: value(vehicle), manufacturer: value(vehicle).map(manufacturer(fromVehicle:)),
                drivers: drivers.map(titleCasedSurname),
                laps: value(laps).flatMap(Int.init),
                time: isRace ? value(total).map(normalizedTime) : value(time).map(normalizedTime),
                gapFirst: value(gap).flatMap { $0 == "-" ? nil : ($0.contains("Lap") ? $0 : "+" + normalizedTime($0)) },
                bestLap: (value(fl) ?? value(time)).map(normalizedTime),
                pitStops: nil,
                retired: (value(status) ?? "").lowercased().contains("retired")
            )
        }
    }

    // MARK: IMSA points

    struct IMSAPoints: Decodable {
        let championship: Championship?
        let classification: [Row]
        struct Championship: Decodable { let year: String? }
        struct Row: Decodable {
            let position: Int?
            let totalPoints: Double?
            let key: String
            enum CodingKeys: String, CodingKey { case position; case totalPoints = "total_points"; case key }
        }
    }

    // MARK: Helpers

    static func stripBOM(_ data: Data) -> Data {
        data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
    }

    /// "6:01'01.299" / "1'31.159" (WEC) → "6:01:01.299" / "1:31.159".
    static func normalizedTime(_ time: String) -> String {
        time.replacingOccurrences(of: "'", with: ":")
    }

    /// Seconds in "10:00:50.625", "1:12.179" or "72.179"; infinity when unparseable.
    static func seconds(_ time: String?) -> Double {
        guard let time = time?.replacingOccurrences(of: "'", with: ":"), !time.isEmpty else { return .infinity }
        var total = 0.0
        for part in time.split(separator: ":") {
            guard let value = Double(part) else { return .infinity }
            total = total * 60 + value
        }
        return total
    }

    /// "Sébastien BUEMI" → "Sébastien Buemi".
    static func titleCasedSurname(_ name: String) -> String {
        name.split(separator: " ").map { word in
            word.count > 1 && word == word.uppercased() && word.contains(where: \.isLetter)
                ? word.prefix(1) + word.dropFirst().lowercased()
                : Substring(word)
        }.joined(separator: " ")
    }

    /// "Toyota TR010 Hybrid" → "Toyota"; WEC's CSV has no manufacturer column.
    static func manufacturer(fromVehicle vehicle: String) -> String {
        let known = ["Aston Martin", "Mercedes-AMG", "McLaren", "Lamborghini", "Ferrari", "Porsche", "Toyota", "Cadillac",
                     "BMW", "Alpine", "Peugeot", "Ford", "Corvette", "Lexus", "Acura", "Genesis", "Oreca", "Ligier"]
        return known.first { vehicle.localizedCaseInsensitiveContains($0) } ?? String(vehicle.split(separator: " ").first ?? "")
    }

    static func nonEmpty(_ string: String?) -> String? {
        guard let string = string?.trimmingCharacters(in: .whitespaces), !string.isEmpty else { return nil }
        return string
    }

    private static let folderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        // Local track time; the caller shifts it to UTC.
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMddHHmm"
        return f
    }()
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
