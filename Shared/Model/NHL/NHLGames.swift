/* 
Copyright (c) 2021 Swift Models Generated from JSON powered by http://www.json4swift.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For support, please feel free to contact me at https://www.linkedin.com/in/syedabsar

*/

import Foundation
struct NHLGames : Codable {
	let id : String?
	let title : String?
	let status : String?
	let coverage : String?
	let scheduled : String?
	let home_points : Int?
	let away_points : Int?
	let sr_id : String?
	let reference : String?
	let venue : NHLVenue?
	let broadcasts : [NHLBroadcasts]?
	let home : NHLHome?
	let away : NHLAway?

	enum CodingKeys: String, CodingKey {

		case id = "id"
		case title = "title"
		case status = "status"
		case coverage = "coverage"
		case scheduled = "scheduled"
		case home_points = "home_points"
		case away_points = "away_points"
		case sr_id = "sr_id"
		case reference = "reference"
		case venue = "venue"
		case broadcasts = "broadcasts"
		case home = "home"
		case away = "away"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id = try values.decodeIfPresent(String.self, forKey: .id)
		title = try values.decodeIfPresent(String.self, forKey: .title)
		status = try values.decodeIfPresent(String.self, forKey: .status)
		coverage = try values.decodeIfPresent(String.self, forKey: .coverage)
		scheduled = try values.decodeIfPresent(String.self, forKey: .scheduled)
		home_points = try values.decodeIfPresent(Int.self, forKey: .home_points)
		away_points = try values.decodeIfPresent(Int.self, forKey: .away_points)
		sr_id = try values.decodeIfPresent(String.self, forKey: .sr_id)
		reference = try values.decodeIfPresent(String.self, forKey: .reference)
		venue = try values.decodeIfPresent(NHLVenue.self, forKey: .venue)
		broadcasts = try values.decodeIfPresent([NHLBroadcasts].self, forKey: .broadcasts)
		home = try values.decodeIfPresent(NHLHome.self, forKey: .home)
		away = try values.decodeIfPresent(NHLAway.self, forKey: .away)
	}

}
