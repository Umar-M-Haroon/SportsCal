/* 
Copyright (c) 2021 Swift Models Generated from JSON powered by http://www.json4swift.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For support, please feel free to contact me at https://www.linkedin.com/in/syedabsar

*/

import Foundation
struct NFLGames : Codable {
	let id : String?
	let status : String?
	let reference : String?
	let number : Int?
	let scheduled : String?
	let attendance : Int?
	let utc_offset : Int?
	let entry_mode : String?
	let weather : String?
	let sr_id : String?
	let venue : NFLVenue?
	let home : NFLHome?
	let away : NFLAway?
	let broadcast : NFLBroadcast?
	let scoring : NFLScoring?

	enum CodingKeys: String, CodingKey {

		case id = "id"
		case status = "status"
		case reference = "reference"
		case number = "number"
		case scheduled = "scheduled"
		case attendance = "attendance"
		case utc_offset = "utc_offset"
		case entry_mode = "entry_mode"
		case weather = "weather"
		case sr_id = "sr_id"
		case venue = "venue"
		case home = "home"
		case away = "away"
		case broadcast = "broadcast"
		case scoring = "scoring"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id = try values.decodeIfPresent(String.self, forKey: .id)
		status = try values.decodeIfPresent(String.self, forKey: .status)
		reference = try values.decodeIfPresent(String.self, forKey: .reference)
		number = try values.decodeIfPresent(Int.self, forKey: .number)
		scheduled = try values.decodeIfPresent(String.self, forKey: .scheduled)
		attendance = try values.decodeIfPresent(Int.self, forKey: .attendance)
		utc_offset = try values.decodeIfPresent(Int.self, forKey: .utc_offset)
		entry_mode = try values.decodeIfPresent(String.self, forKey: .entry_mode)
		weather = try values.decodeIfPresent(String.self, forKey: .weather)
		sr_id = try values.decodeIfPresent(String.self, forKey: .sr_id)
		venue = try values.decodeIfPresent(NFLVenue.self, forKey: .venue)
		home = try values.decodeIfPresent(NFLHome.self, forKey: .home)
		away = try values.decodeIfPresent(NFLAway.self, forKey: .away)
		broadcast = try values.decodeIfPresent(NFLBroadcast.self, forKey: .broadcast)
		scoring = try values.decodeIfPresent(NFLScoring.self, forKey: .scoring)
	}

}
