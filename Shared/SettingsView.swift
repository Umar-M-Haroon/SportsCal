//
//  SettingsView.swift
//  SettingsView
//
//  Created by Umar Haroon on 8/8/21.
//

import SwiftUI
import Combine



struct SettingsView: View {
    @EnvironmentObject var appStorage: UserDefaultStorage
//    @AppStorage("dateFormatString") var dateFormatString: String = "E, dd.MM.yy"
//    @AppStorage("duration") var durations: Durations = .oneWeek
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
                            Text("Hide events more than ")
                        Spacer()
                        Menu("\(appStorage.durations.rawValue) away") {
                            Button(Durations.oneWeek.rawValue) {
                                appStorage.durations = .oneWeek
                            }
                            Button(Durations.twoWeeks.rawValue) {
                                appStorage.durations = .twoWeeks
                            }
                            Button(Durations.threeWeeks.rawValue) {
                                appStorage.durations = .threeWeeks
                            }
                            Button(Durations.oneMonth.rawValue) {
                                appStorage.durations = .oneMonth
                            }
                            Button(Durations.twoMonths.rawValue) {
                                appStorage.durations = .twoMonths
                            }
                            Button(Durations.sixMonths.rawValue) {
                                appStorage.durations = .sixMonths
                            }
                            Button(Durations.oneYear.rawValue) {
                                appStorage.durations = .oneYear
                            }
                            
                        }
                        .disabled(SubscriptionManager.shared.subscriptionStatus == .notSubscribed)
                    }
                    Toggle("Hide Past Events", isOn: appStorage.$hidePastEvents)
                        .disabled(SubscriptionManager.shared.subscriptionStatus == .notSubscribed)
                }
                Section(header: Text("Scores")) {
                    HStack {
                        Text("Show scores for games ")
                        Spacer()
                        Menu("\(appStorage.durations.rawValue) old") {
                            Button(Durations.oneWeek.rawValue) {
                                appStorage.durations = .oneWeek
                            }
                            Button(Durations.twoWeeks.rawValue) {
                                appStorage.durations = .twoWeeks
                            }
                            Button(Durations.threeWeeks.rawValue) {
                                appStorage.durations = .threeWeeks
                            }
                            Button(Durations.oneMonth.rawValue) {
                                appStorage.durations = .oneMonth
                            }
                            Button(Durations.twoMonths.rawValue) {
                                appStorage.durations = .twoMonths
                            }
                            Button(Durations.sixMonths.rawValue) {
                                appStorage.durations = .sixMonths
                            }
                            Button(Durations.oneYear.rawValue) {
                                appStorage.durations = .oneYear
                            }
                            
                        }
                        .disabled(SubscriptionManager.shared.subscriptionStatus == .notSubscribed)
                    }

                }
//                NavigationLink("Date Format") {
                    Picker.init("Date Format", selection: appStorage.$dateFormat) {
                        ForEach(DateFormatStrings.allCases) { dateFormat in
                            Text(dateFormat.toExample())
                                .tag(dateFormat)
                        }
                    }
                    .pickerStyle(.inline)
//                }
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
