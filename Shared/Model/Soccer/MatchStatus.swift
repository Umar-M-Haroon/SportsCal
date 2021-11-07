import Foundation

enum MatchStatus: String, Codable {
    case aet = "aet"
    case ap = "ap"
    case ended = "ended"
    case notStarted = "not_started"
    case postponed = "postponed"
}
