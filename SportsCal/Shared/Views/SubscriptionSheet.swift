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
            // RevenueCatUI's PaywallView has no intrinsic size on macOS, so a
            // plain sheet renders it tiny. Give it a sensible window-sized frame.
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 520, minHeight: 600, idealHeight: 680)
            #endif
    }
}

#Preview {
    SubscriptionSheet(subscriptionPresented: .constant(true))
}
