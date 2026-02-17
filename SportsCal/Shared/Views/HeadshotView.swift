//
//  HeadshotView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/12/26.
//

import SwiftUI

/// Reusable circular headshot image with gray person.fill placeholder
struct HeadshotView: View {
    let url: String?
    var size: CGFloat = 24

    var body: some View {
        if let urlString = url, let imageURL = URL(string: urlString) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .padding(size * 0.15)
            .frame(width: size, height: size)
            .foregroundColor(.secondary)
            .background(Color.gray.opacity(0.2))
            .clipShape(Circle())
    }
}
