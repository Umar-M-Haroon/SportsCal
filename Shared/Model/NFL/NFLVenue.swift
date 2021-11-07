/* 
Copyright (c) 2021 Swift Models Generated from JSON powered by http://www.json4swift.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For support, please feel free to contact me at https://www.linkedin.com/in/syedabsar

*/

import Foundation
struct NFLVenue : Codable {
	let id : String?
	let name : String?
	let city : String?
	let state : String?
	let country : String?
	let zip : String?
	let address : String?
	let capacity : Int?
	let surface : String?
	let roof_type : String?
	let sr_id : String?
	let location : NFLLocation?

	enum CodingKeys: String, CodingKey {

		case id = "id"
		case name = "name"
		case city = "city"
		case state = "state"
		case country = "country"
		case zip = "zip"
		case address = "address"
		case capacity = "capacity"
		case surface = "surface"
		case roof_type = "roof_type"
		case sr_id = "sr_id"
		case location = "location"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id = try values.decodeIfPresent(String.self, forKey: .id)
		name = try values.decodeIfPresent(String.self, forKey: .name)
		city = try values.decodeIfPresent(String.self, forKey: .city)
		state = try values.decodeIfPresent(String.self, forKey: .state)
		country = try values.decodeIfPresent(String.self, forKey: .country)
		zip = try values.decodeIfPresent(String.self, forKey: .zip)
		address = try values.decodeIfPresent(String.self, forKey: .address)
		capacity = try values.decodeIfPresent(Int.self, forKey: .capacity)
		surface = try values.decodeIfPresent(String.self, forKey: .surface)
		roof_type = try values.decodeIfPresent(String.self, forKey: .roof_type)
		sr_id = try values.decodeIfPresent(String.self, forKey: .sr_id)
		location = try values.decodeIfPresent(NFLLocation.self, forKey: .location)
	}

}
