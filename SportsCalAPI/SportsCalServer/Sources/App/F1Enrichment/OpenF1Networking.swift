//
//  OpenF1Networking.swift
//  SportsCalServer
//
//  Created by Umar Haroon on 3/5/26.
//

import Foundation
import Vapor
import Logging

/// Fetches F1 data from the OpenF1 API (circuit images, weather).
/// Base URL: https://api.openf1.org/v1
/// Rate limits: 3 req/s, 30 req/min (free tier). No auth required.
class OpenF1Networking {
    private static let logger = Logger(label: "com.sportscal.openf1")
    private static let baseURL = "https://api.openf1.org/v1"

    // MARK: - Meeting (circuit images)

    struct Meeting: Decodable {
        let meeting_key: Int?
        let meeting_name: String?
        let location: String?
        let country_name: String?
        let circuit_short_name: String?
        let circuit_image: String?
    }

    /// Fetches meetings for a season. Returns mapping of meeting_name → circuit_image URL.
    /// This gives us track layout images that no other free API provides.
    static func getCircuitImages(client: some Client, year: Int) async -> [String: String] {
        let url = "\(baseURL)/meetings?year=\(year)"
        do {
            let response = try await client.get(URI(string: url))
            let meetings = try response.content.decode([Meeting].self)
            var imageMap: [String: String] = [:]
            for meeting in meetings {
                if let name = meeting.meeting_name, let imageURL = meeting.circuit_image, !imageURL.isEmpty {
                    imageMap[name] = imageURL
                }
            }
            logger.info("OpenF1 circuit images fetched", metadata: [
                "year": "\(year)",
                "count": "\(imageMap.count)"
            ])
            return imageMap
        } catch {
            logger.error("OpenF1 circuit images fetch failed", metadata: [
                "year": "\(year)",
                "error": "\(error)"
            ])
            return [:]
        }
    }
}
