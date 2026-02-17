//
//  SubscriptionRequiredView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/26/23.
//

import SwiftUI

struct SubscriptionRequiredView: View {
    @Binding var sheetType: SheetType?
    var body: some View {
        VStack {
            Image(systemName: "lock.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 300, height: 300)
                .foregroundStyle(.white)
            Text("SportsCal Pro Subscription Required")
                .foregroundStyle(.white)
            Button("Subscribe", action: {
                sheetType = .paywall
            })
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

#Preview {
    SubscriptionRequiredView(sheetType: .constant(nil))
}
