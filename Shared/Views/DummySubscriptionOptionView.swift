//
//  DummySubscriptionOptionView.swift
//  SportsCal
//
//  Created by Umar Haroon on 4/6/22.
//

import SwiftUI
import SportsCalModel
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
                Button("Start Now") {
                    
                }
                .buttonStyle(.borderedProminent)

        }

    }
}

struct DummySubscriptionOptionView_Previews: PreviewProvider {
    static var previews: some View {
        DummySubscriptionOptionView()
    }
}
