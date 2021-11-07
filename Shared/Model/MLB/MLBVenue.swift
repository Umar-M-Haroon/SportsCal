/* 
Copyright (c) 2021 Swift Models Generated from JSON powered by http://www.json4swift.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For support, please feel free to contact me at https://www.linkedin.com/in/syedabsar

*/

import Foundation
struct MLBVenue : Codable {
	let name : String?
	let market : String?
	let capacity : Int?
	let surface : String?
	let address : String?
	let city : String?
	let state : String?
	let zip : String?
	let country : String?
	let id : String?
	let field_orientation : String?
	let stadium_type : String?
	let location : MLBLocation?

	enum CodingKeys: String, CodingKey {

		case name = "name"
		case market = "market"
		case capacity = "capacity"
		case surface = "surface"
		case address = "address"
		case city = "city"
		case state = "state"
		case zip = "zip"
		case country = "country"
		case id = "id"
		case field_orientation = "field_orientation"
		case stadium_type = "stadium_type"
		case location = "location"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		name = try values.decodeIfPresent(String.self, forKey: .name)
		market = try values.decodeIfPresent(String.self, forKey: .market)
		capacity = try values.decodeIfPresent(Int.self, forKey: .capacity)
		surface = try values.decodeIfPresent(String.self, forKey: .surface)
		address = try values.decodeIfPresent(String.self, forKey: .address)
		city = try values.decodeIfPresent(String.self, forKey: .city)
		state = try values.decodeIfPresent(String.self, forKey: .state)
		zip = try values.decodeIfPresent(String.self, forKey: .zip)
		country = try values.decodeIfPresent(String.self, forKey: .country)
		id = try values.decodeIfPresent(String.self, forKey: .id)
		field_orientation = try values.decodeIfPresent(String.self, forKey: .field_orientation)
		stadium_type = try values.decodeIfPresent(String.self, forKey: .stadium_type)
		location = try values.decodeIfPresent(MLBLocation.self, forKey: .location)
	}

}
