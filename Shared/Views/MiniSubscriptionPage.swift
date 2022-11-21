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
        VStack() {
            Text("SportsCal Pro")
                .font(.title2)
                .bold()
                MiniFeatureView(featureName: "Push Notifications", featureDescription: "Get notified when tasks are added and completed", imageName: "app.badge.fill", color: .red)
                
                MiniFeatureView(featureName: "Multiple Sports", featureDescription: "See multiple sports at once", imageName: "sportscourt.fill", color: .green)
                
                MiniFeatureView(featureName: "Calendar Integration", featureDescription: "See events that are more than a week away", imageName: "calendar.circle.fill", color: .blue)
            Button(action: {
                subscriptionPresented = true
            }, label: {
                Text("Unlock Pro")
                    .bold()
                    .frame(maxWidth: .infinity,alignment: .center)

            })
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        
    }
}

struct MiniSubscriptionPage_Previews: PreviewProvider {
    static var previews: some View {
        MiniSubscriptionPage(subscriptionPresented: .constant(false))
    }
}
