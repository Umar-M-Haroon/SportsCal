//
//  SettingsView.swift
//  SettingsView
//
//  Created by Umar Haroon on 8/8/21.
//

import SwiftUI
import Combine



struct SettingsView: View {
//    var settings: SettingsObject
    @AppStorage("hidesPastEvents") var hidePastEvents: Bool = false
    @AppStorage("dateFormatString") var dateFormatString: String = "E, dd.MM.yy"
    @AppStorage("duration") var durations: Durations = .oneWeek
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Binding var sheetType: SheetType?
    var body: some View {
        NavigationView {
            Form {
                NavigationLink("SportsCal Pro") {
                    SubscriptionPage()
                }
                Section(header: Text("SportsCal Pro Options")) {
                HStack {
                    
                    if #available(iOS 15.0, *) {
                        Text(showAttributedString())
                    } else {
                        Text("Hide events more than \(durations.rawValue)")
                    }
                    Spacer()
                    Menu("\(durations.rawValue) away") {
                        Button(Durations.oneWeek.rawValue) {
                            durations = .oneWeek
                        }
                        Button(Durations.twoWeeks.rawValue) {
                            durations = .twoWeeks
                        }
                        Button(Durations.threeWeeks.rawValue) {
                            durations = .threeWeeks
                        }
                        Button(Durations.oneMonth.rawValue) {
                            durations = .oneMonth
                        }
                        Button(Durations.twoMonths.rawValue) {
                            durations = .twoMonths
                        }
                        Button(Durations.sixMonths.rawValue) {
                            durations = .sixMonths
                        }
                        Button(Durations.oneYear.rawValue) {
                            durations = .oneYear
                        }
                        
                    }
                    .disabled(SubscriptionManager.shared.subscriptionStatus == .notSubscribed)
                }
                Toggle("Hide Past Events", isOn: $hidePastEvents)
                    .disabled(SubscriptionManager.shared.subscriptionStatus == .notSubscribed)
                }
            }
            .navigationBarItems(leading: Button(action: {
                sheetType = nil
            }, label: {
                Text("Done")
            }))
            .navigationTitle("Settings")
        }
    }
    @available(iOS 15.0, *)
    func showAttributedString() -> AttributedString {
        var string = AttributedString("Hide events more than")
        //                string.foregroundColor = .blue
        
        if let range = string.range(of: "1 month") { /// here!
            string[range].foregroundColor = .blue
        }
        return string
    }
}
//
//struct SettingsView_Previews: PreviewProvider {
//    static var previews: some View {
//        SettingsView(shouldShowSettings: Binding(get: {
//            true
//        }, set: val))
//    }
//}
