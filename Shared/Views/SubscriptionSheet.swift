//
//  SubscriptionSheet.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/20/22.
//

import SwiftUI

struct SubscriptionSheet: View {
    @Binding var subscriptionPresented: Bool
    var body: some View {
        NavigationView {
            SubscriptionPage(selectedProduct: SubscriptionManager.shared.monthlySubscription)
                .environmentObject(SubscriptionManager.shared)
                .navigationBarItems(leading: Button(action: {
                    subscriptionPresented = false
                }, label: {
                    Text("Cancel")
                })
                )
        }
    }
}

struct SubscriptionSheet_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionSheet(subscriptionPresented: .constant(false))
    }
}
