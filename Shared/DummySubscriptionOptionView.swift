//
//  DummySubscriptionOptionView.swift
//  SportsCal
//
//  Created by Umar Haroon on 4/6/22.
//

import SwiftUI

struct DummySubscriptionOptionView: View {
    var body: some View {
        HStack {
            Text("1 week trial, then $9.99 every year")
            .font(.headline)
                Text("Save 20%!")
                .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .foregroundColor(.yellow)
                            .opacity(0.8)
                    )
            if #available(iOS 15.0, *) {
                Button("Start Now") {
                    
                }
                .buttonStyle(.borderedProminent)
            } else {
                // Fallback on earlier versions
            }
        }

    }
}

struct DummySubscriptionOptionView_Previews: PreviewProvider {
    static var previews: some View {
        DummySubscriptionOptionView()
    }
}
