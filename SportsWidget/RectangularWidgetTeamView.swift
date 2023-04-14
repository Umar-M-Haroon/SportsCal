//
//  RectangularWidgetTeamView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 3/27/23.
//

import Foundation
import SwiftUI

struct RectangularWidgetTeamView: View {
    var longName: String?
    var isAway: Bool
    var data: Data? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
            }
            if let longName {
                Text(longName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
