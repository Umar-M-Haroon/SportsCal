/* 
Copyright (c) 2021 Swift Models Generated from JSON powered by http://www.json4swift.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For support, please feel free to contact me at https://www.linkedin.com/in/syedabsar

*/

import Foundation
struct NBABroadcasts: Codable {
    internal init(network: String?, type: String?, locale: String?, channel: String?) {
        self.network = network
        self.type = type
        self.locale = locale
        self.channel = channel
    }
    
	let network: String?
	let type: String?
	let locale: String?
	let channel: String?

	enum CodingKeys: String, CodingKey {

		case network = "network"
		case type = "type"
		case locale = "locale"
		case channel = "channel"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		network = try values.decodeIfPresent(String.self, forKey: .network)
		type = try values.decodeIfPresent(String.self, forKey: .type)
		locale = try values.decodeIfPresent(String.self, forKey: .locale)
		channel = try values.decodeIfPresent(String.self, forKey: .channel)
	}

}
