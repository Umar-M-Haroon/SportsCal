//
//  SubscriptionSheet.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/20/22.
//

import SwiftUI
import RevenueCatUI

struct SubscriptionSheet: View {
    @Binding var subscriptionPresented: Bool

    var body: some View {
        PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { _ in
                subscriptionPresented = false
            }
            .onRestoreCompleted { _ in
                subscriptionPresented = false
            }
    }
}

#Preview {
    SubscriptionSheet(subscriptionPresented: .constant(true))
}
