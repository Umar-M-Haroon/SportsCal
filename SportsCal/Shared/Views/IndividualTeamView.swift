//
//  IndividualTeamView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/27/22.
//

import SwiftUI
import SportsCalModel
import NukeUI

private func resolvedBadgeURL(_ urlString: String) -> URL? {
    if urlString.contains("thesportsdb.com") {
        return URL(string: urlString + "/preview")
    }
    return URL(string: urlString)
}

struct IndividualTeamView: View {
    var teamURL: String?
    var shortName: String?
    var longName: String?
    var score: Int?
    var isWinning: Bool
    var isAway: Bool
    var data: Data? = nil
    // Fallback logo view when URL is missing
    private var fallbackLogo: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 40, height: 40)
            if let shortName {
                Text(String(shortName.prefix(3)))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
            } else if let longName {
                Text(String(longName.prefix(3)))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }

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
                        LazyImage(request: ImageRequest(url: resolvedBadgeURL(teamURL), processors: [.resize(size: CGSize(width: 40, height: 40))])) { state in
                            if let image = state.image {
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 40, height: 40)
                            } else if state.error != nil {
                                // Show fallback if image load fails
                                fallbackLogo
                            } else {
                                ProgressView()
                            }
                        }
                    } else if let data {
                        #if os(iOS)
                        if let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 35, height: 35)
                        }
                        #else
                        if let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 35, height: 35)
                        }
                        #endif
                    } else {
                        // Show fallback when no URL or data
                        fallbackLogo
                    }
                } else {
                    if let teamURL {
                        LazyImage(request: ImageRequest(url: resolvedBadgeURL(teamURL), processors: [.resize(size: CGSize(width: 40, height: 40))])) { state in
                            if let image = state.image {
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 40, height: 40)
                            } else if state.error != nil {
                                // Show fallback if image load fails
                                fallbackLogo
                            } else {
                                ProgressView()
                            }
                        }
                    } else if let data {
                        #if os(iOS)
                        if let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 35, height: 35)
                        }
                        #else
                        if let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 35, height: 35)
                        }
                        #endif
                    } else {
                        // Show fallback when no URL or data
                        fallbackLogo
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

#Preview {
    IndividualTeamView(isWinning: false, isAway: true)
}
