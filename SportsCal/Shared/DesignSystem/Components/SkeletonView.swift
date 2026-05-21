//
//  SkeletonView.swift
//  SportsCal — Design System v1.0
//
//  Loading placeholders that match Heavy B layout — list rows and grid
//  tiles. Shimmer honors Reduce Motion (falls back to static fade).
//

import SwiftUI

public struct SkeletonRow: View {
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            RoundedRectangle.appShape(.appRadiusXS)
                .fill(Color.appAlt)
                .frame(width: 120, height: 10)
            RoundedRectangle.appShape(.appRadiusXS)
                .fill(Color.appAlt)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
            RoundedRectangle.appShape(.appRadiusXS)
                .fill(Color.appAlt)
                .frame(width: 200, height: 14)
        }
        .appCard()
        .opacity(shimmer ? 0.55 : 1.0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
        .accessibilityLabel(Text("Loading"))
    }
}

public struct SkeletonTile: View {
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle.appShape(.appRadiusXS)
                .fill(Color.appAlt)
                .frame(width: 60, height: 8)
            RoundedRectangle.appShape(.appRadiusXS)
                .fill(Color.appAlt)
                .frame(maxWidth: .infinity)
                .frame(height: 14)
            RoundedRectangle.appShape(.appRadiusXS)
                .fill(Color.appAlt)
                .frame(width: 80, height: 16)
        }
        .padding(.appSpace3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle.appShape(.appRadiusSM)
                .fill(Color.appAlt.opacity(0.6))
        )
        .opacity(shimmer ? 0.55 : 1.0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
        .accessibilityLabel(Text("Loading"))
    }
}
