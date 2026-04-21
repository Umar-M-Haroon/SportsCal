//
//  MiniSubscriptionPage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/19/22.
//

import SwiftUI

struct MiniSubscriptionPage: View {
    @Binding var subscriptionPresented: Bool

    var body: some View {
        VStack {
            Text("Scoreline Pro")
                .font(.title2)
                .bold()
            MiniFeatureView(featureName: "Ad-Free Experience", featureDescription: "Remove all ads", imageName: "eye.slash.fill", color: .purple)
            MiniFeatureView(featureName: "Push Notifications", featureDescription: "Get notified about games", imageName: "app.badge.fill", color: .red)
            MiniFeatureView(featureName: "Pro Settings", featureDescription: "Customize event visibility and countdowns", imageName: "slider.horizontal.3", color: .blue)
            Button {
                subscriptionPresented = true
            } label: {
                Text("Unlock Pro")
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Feature Row

struct MiniFeatureView: View {
    var featureName: String
    var featureDescription: String
    var imageName: String
    var color: Color?

    var body: some View {
        HStack {
            Image(systemName: imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 45, height: 45)
                .foregroundColor(color)
            Text(featureName)
                .font(.headline)
                .padding()
            Spacer()
        }
    }
}

#Preview {
    MiniSubscriptionPage(subscriptionPresented: .constant(false))
}
