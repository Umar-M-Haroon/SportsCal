//
//  IndividualTeamView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/27/22.
//

import SwiftUI
import SportsCalModel
import CachedAsyncImage
struct IndividualTeamView: View {
    var teamURL: String?
    var shortName: String?
    var longName: String?
    var score: Int?
    var isWinning: Bool
    var isAway: Bool
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                if !isAway {
                    if let score = score, isWinning {
                        Text("\(score)")
                            .font(.system(size: 24))
                            .fontWeight(.heavy)
                    } else if let score = score, !isWinning  {
                        Text("\(score)")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                    if let teamURL {
                        CachedAsyncImage(url: URL(string: "\(teamURL)/preview")) { image in
                            image.resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                        } placeholder: {
                            ProgressView()
                        }
                    }
                } else {
                    if let teamURL {
                        CachedAsyncImage(url: URL(string: "\(teamURL)/preview")) { image in
                            image.resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                        } placeholder: {
                            ProgressView()
                        }
                    }
                    if let score = score, isWinning {
                        Text("\(score)")
                            .font(.system(size: 24))
                            .fontWeight(.heavy)
                    } else if let score = score, !isWinning  {
                        Text("\(score)")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                }
                
                
            }
            if let shortName {
                Text(shortName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let longName {
                Text(longName)
                    .foregroundColor(.secondary)
                    .font(.caption2)
            }
        }
    }
}

struct IndividualTeamView_Previews: PreviewProvider {
    static var previews: some View {
        IndividualTeamView(isWinning: false, isAway: true)
    }
}
