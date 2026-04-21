//
//  InjuryReport.swift
//  SportsCalModel
//
//  Created by Umar Haroon on 4/19/26.
//

import Foundation

public struct InjuryReport: Codable, Equatable, Hashable {
    public let playerName: String
    public let position: String?
    public let status: String
    public let detail: String?
    public let comment: String?
    public let headshot: String?
    public let returnDate: String?
    public let date: String?

    public init(
        playerName: String,
        position: String? = nil,
        status: String,
        detail: String? = nil,
        comment: String? = nil,
        headshot: String? = nil,
        returnDate: String? = nil,
        date: String? = nil
    ) {
        self.playerName = playerName
        self.position = position
        self.status = status
        self.detail = detail
        self.comment = comment
        self.headshot = headshot
        self.returnDate = returnDate
        self.date = date
    }
}
