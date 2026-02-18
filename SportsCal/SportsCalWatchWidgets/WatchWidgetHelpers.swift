//
//  WatchWidgetHelpers.swift
//  SportsCalWatchWidgets
//
//  Re-exports shared helper types from SportsWidget.swift that can't be
//  included directly because SportsWidget.swift contains @main WidgetBundle.
//

import SwiftUI
import SportsCalModel

// MARK: - Cross-Platform Image Helper (watchOS)

func widgetImage(from data: Data) -> Image? {
    guard let img = UIImage(data: data) else { return nil }
    return Image(uiImage: img)
}

// MARK: - Cell Background

var widgetCellBackground: Color {
    Color.gray.opacity(0.2)
}

// MARK: - Team Badge Views

struct WidgetTeamView: View {
    var shortName: String?
    var longName: String?
    var isAway: Bool
    var data: Data? = nil
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if shortName == nil && !isAway {
                    Spacer()
                }
                if let data, let image = widgetImage(from: data) {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                }
                if shortName == nil && isAway {
                    Spacer()
                }
            }
            if let shortName {
                Text(shortName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if let longName {
                Text(longName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: isAway ? .leading : .trailing)
            }
        }
    }
}

struct TinyWidgetTeamView: View {
    var shortName: String?
    var longName: String?
    var isAway: Bool
    var data: Data? = nil
    var showText: Bool = true
    var body: some View {
        VStack(spacing: 0) {
            if let data, let image = widgetImage(from: data) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            }
            if showText {
                if let shortName {
                    Text(shortName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else if let longName {
                    Text(longName.uppercased())
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
