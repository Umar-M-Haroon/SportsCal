/* 
Copyright (c) 2021 Swift Models Generated from JSON powered by http://www.json4swift.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For support, please feel free to contact me at https://www.linkedin.com/in/syedabsar

*/

import Foundation
struct NFLPeriods : Codable {
	let period_type : String?
	let id : String?
	let number : Int?
	let sequence : Int?
	let home_points : Int?
	let away_points : Int?

	enum CodingKeys: String, CodingKey {

		case period_type = "period_type"
		case id = "id"
		case number = "number"
		case sequence = "sequence"
		case home_points = "home_points"
		case away_points = "away_points"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		period_type = try values.decodeIfPresent(String.self, forKey: .period_type)
		id = try values.decodeIfPresent(String.self, forKey: .id)
		number = try values.decodeIfPresent(Int.self, forKey: .number)
		sequence = try values.decodeIfPresent(Int.self, forKey: .sequence)
		home_points = try values.decodeIfPresent(Int.self, forKey: .home_points)
		away_points = try values.decodeIfPresent(Int.self, forKey: .away_points)
	}

}
