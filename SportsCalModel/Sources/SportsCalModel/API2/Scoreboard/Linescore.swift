// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let linescore = try? newJSONDecoder().decode(Linescore.self, from: jsonData)

import Foundation

// MARK: - Linescore
public struct Linescore: Codable {
    public var value: Double?

    public init(value: Double?) {
        self.value = value
    }
}
