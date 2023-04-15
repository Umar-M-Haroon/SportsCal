//
//  IndividualTeamView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/27/22.
//

import SwiftUI
import SportsCalModel
import NukeUI
struct IndividualTeamView: View {
    var teamURL: String?
    var shortName: String?
    var longName: String?
    var score: Int?
    var isWinning: Bool
    var isAway: Bool
    var data: Data? = nil
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
                        LazyImage(request: ImageRequest(url: URL(string: "\(teamURL)/preview"), processors: [.resize(size: CGSize(width: 40, height: 40))])) { state in
                            if let image = state.image {
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(minWidth: 20, maxWidth: 40, minHeight: 20, maxHeight: 40)
                            } else {
                                ProgressView()
                            }
                        }
                    }
                    if let data, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 35, height: 35)
                    }
                } else {
                    if let teamURL {
                        LazyImage(request: ImageRequest(url: URL(string: "\(teamURL)/preview"), processors: [.resize(size: CGSize(width: 40, height: 40))])) { state in
                            if let image = state.image {
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(minWidth: 20, maxWidth: 40, minHeight: 20, maxHeight: 40)
                            } else {
                                ProgressView()
                            }
                        }
                    } else if let data, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 35, height: 35)
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
            .frame(maxWidth: .infinity, alignment: isAway ? .leading : .trailing)
            if let shortName {
                Text(shortName)
                    .font(.headline)
                    .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: isAway ? .leading : .trailing)
            } else if let longName {
                Text(longName)
                    .foregroundColor(.secondary)
                    .font(.headline)
            .frame(maxWidth: .infinity, alignment: isAway ? .leading : .trailing)
            }
        }
    }
}

struct IndividualTeamView_Previews: PreviewProvider {
    static var previews: some View {
        IndividualTeamView(isWinning: false, isAway: true)
    }
}
