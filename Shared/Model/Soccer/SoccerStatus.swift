import Foundation

enum SoccerStatus: String, Codable {
    case closed = "closed"
    case notStarted = "not_started"
    case postponed = "postponed"
    case live = "live"
}
