// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let f1 = try? newJSONDecoder().decode(F1.self, from: jsonData)

import Foundation

// MARK: - F1
struct F1: Codable {
    let generatedAt: String?
    let schema: String?
    let stage: F1Stage?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case schema, stage
    }
}
