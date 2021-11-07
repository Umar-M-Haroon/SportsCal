/* 
Copyright (c) 2021 Swift Models Generated from JSON powered by http://www.json4swift.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For support, please feel free to contact me at https://www.linkedin.com/in/syedabsar

*/

import Foundation
struct MLBGames : Codable {
	let id : String?
	let status : String?
	let coverage : String?
	let game_number : Int?
	let day_night : String?
	let scheduled : String?
	let home_team : String?
	let away_team : String?
	let ps_round : String?
	let ps_game : String?
	let attendance : Int?
	let duration : String?
	let double_header : Bool?
	let entry_mode : String?
	let reference : String?
	let venue : MLBVenue?
	let home : NBAHome?
	let away : MLBAway?
	let broadcast : MLBBroadcast?

	enum CodingKeys: String, CodingKey {

		case id = "id"
		case status = "status"
		case coverage = "coverage"
		case game_number = "game_number"
		case day_night = "day_night"
		case scheduled = "scheduled"
		case home_team = "home_team"
		case away_team = "away_team"
		case ps_round = "ps_round"
		case ps_game = "ps_game"
		case attendance = "attendance"
		case duration = "duration"
		case double_header = "double_header"
		case entry_mode = "entry_mode"
		case reference = "reference"
		case venue = "venue"
		case home = "home"
		case away = "away"
		case broadcast = "broadcast"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id = try values.decodeIfPresent(String.self, forKey: .id)
		status = try values.decodeIfPresent(String.self, forKey: .status)
		coverage = try values.decodeIfPresent(String.self, forKey: .coverage)
		game_number = try values.decodeIfPresent(Int.self, forKey: .game_number)
		day_night = try values.decodeIfPresent(String.self, forKey: .day_night)
		scheduled = try values.decodeIfPresent(String.self, forKey: .scheduled)
		home_team = try values.decodeIfPresent(String.self, forKey: .home_team)
		away_team = try values.decodeIfPresent(String.self, forKey: .away_team)
		ps_round = try values.decodeIfPresent(String.self, forKey: .ps_round)
		ps_game = try values.decodeIfPresent(String.self, forKey: .ps_game)
		attendance = try values.decodeIfPresent(Int.self, forKey: .attendance)
		duration = try values.decodeIfPresent(String.self, forKey: .duration)
		double_header = try values.decodeIfPresent(Bool.self, forKey: .double_header)
		entry_mode = try values.decodeIfPresent(String.self, forKey: .entry_mode)
		reference = try values.decodeIfPresent(String.self, forKey: .reference)
		venue = try values.decodeIfPresent(MLBVenue.self, forKey: .venue)
		home = try values.decodeIfPresent(NBAHome.self, forKey: .home)
		away = try values.decodeIfPresent(MLBAway.self, forKey: .away)
		broadcast = try values.decodeIfPresent(MLBBroadcast.self, forKey: .broadcast)
	}

}
