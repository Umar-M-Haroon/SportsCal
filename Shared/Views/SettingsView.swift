//
//  SettingsView.swift
//  SettingsView
//
//  Created by Umar Haroon on 8/8/21.
//

import SwiftUI
import Combine
import SportsCalModel


struct SettingsView: View {
    @EnvironmentObject var appStorage: UserDefaultStorage
    var subscriptionManager = SubscriptionManager.shared
    @Binding var sheetType: SheetType?
    @EnvironmentObject var viewModel: GameViewModel
    var datesAndFormats: [(Date, DateFormatter.Style)] {
        let dates = [Date.now, Date.dateAfterDaysFromNow(days: 1), Date.dateAfterDaysFromNow(days: 2), Date.dateAfterDaysFromNow(days: 3)]
        let formats = [DateFormatter.Style.short, .medium, .full, .long]
        return dates.enumerated().map({($1, formats[$0])})
    }
    var isTestFlight: Bool {
        guard let path = Bundle.main.appStoreReceiptURL?.path else {
            return false
        }
        return path.contains("sandboxReceipt")
    }
    var body: some View {
        NavigationView {
            Form {
#if DEBUG
                Toggle("Debug Mode", isOn: appStorage.$debugMode)
                Button("Dump Caches") {
                    do {
                        try viewModel.dumpCaches()
                    } catch {
                        print(error.localizedDescription)
                    }
                }
#endif
                if isTestFlight {
                    Text("You're on a TestFlight build, debug mode is recommended for new features")
                        .font(.headline)
                    Toggle("Debug Mode", isOn: appStorage.$debugMode)
                }
                NavigationLink("SportsCal Pro") {
                    SubscriptionPage(selectedProduct: subscriptionManager.monthlySubscription)
                        .environmentObject(subscriptionManager)
                }
                NavigationLink("Visible soccer competitions") {
                    CompetitionPage(competitions: Leagues.allCases.filter({$0.isSoccer}).map({$0.leagueName}))
                        .environmentObject(appStorage)
                }
                Section(header: Text("SportsCal Pro Options")) {
                    HStack {
                        Text("Hide events more than ")
                        Spacer()
                        Menu("\(appStorage.durations.rawValue) away") {
                            Button(Durations.oneDay.rawValue) {
                                appStorage.durations = .oneDay
                            }
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
                    Toggle("Hide past events", isOn: appStorage.$hidePastEvents)
                        .disabled(SubscriptionManager.shared.subscriptionStatus == .notSubscribed)
                    Toggle("Show countdown", isOn: appStorage.$showStartTime)
                        .disabled(SubscriptionManager.shared.subscriptionStatus == .notSubscribed)
                    .disabled(SubscriptionManager.shared.subscriptionStatus == .notSubscribed)
                }
                Section(header: Text("Scores")) {
                    HStack {
                        Text("Show past games ")
                        Spacer()
                        Menu("\(appStorage.hidePastGamesDuration.rawValue) old") {
                            Button(Durations.oneDay.rawValue) {
                                appStorage.hidePastGamesDuration = .oneDay
                            }
                            Button(Durations.oneWeek.rawValue) {
                                appStorage.hidePastGamesDuration = .oneWeek
                            }
                            Button(Durations.twoWeeks.rawValue) {
                                appStorage.hidePastGamesDuration = .twoWeeks
                            }
                            Button(Durations.threeWeeks.rawValue) {
                                appStorage.hidePastGamesDuration = .threeWeeks
                            }
                            Button(Durations.oneMonth.rawValue) {
                                appStorage.hidePastGamesDuration = .oneMonth
                            }
                            Button(Durations.twoMonths.rawValue) {
                                appStorage.hidePastGamesDuration = .twoMonths
                            }
                            Button(Durations.sixMonths.rawValue) {
                                appStorage.hidePastGamesDuration = .sixMonths
                            }
                            Button(Durations.oneYear.rawValue) {
                                appStorage.hidePastGamesDuration = .oneYear
                            }
                            
                        }
                    }
                    .disabled(appStorage.hidePastEvents)

                }
                Toggle(isOn: appStorage.$useRelativeValue, label: {
                    Text("Use Relative Time")
                })
                Picker.init("Date Format", selection: appStorage.$dateFormat) {
                    ForEach(datesAndFormats, id: \.0) { (date, format) in
                        Text(format.toExample(date: date))
                            .tag(Int(format.rawValue))
                    }
                }
                Section("Preview", content: {
                    ForEach([Date.now, Date.dateAfterDaysFromNow(days: 1), Date.dateAfterDaysFromNow(days: 2), Date.dateAfterDaysFromNow(days: 3)], id: \.self) { date in
                        Text(formatFromStorage(date: date, isRelative: appStorage.useRelativeValue))
                    }
                })
                .pickerStyle(.inline)
            }
            .navigationBarItems(leading: Button(action: {
                sheetType = nil
            }, label: {
                Text("Done")
            }))
            .navigationTitle("Settings")
            .onAppear {
                if isTestFlight {
                    appStorage.debugMode = true
                }
            }
        }
    }
    
    func showAttributedString() -> AttributedString {
        var string = AttributedString("Hide events more than")
        //                string.foregroundColor = .blue
        
        if let range = string.range(of: "1 month") { /// here!
            string[range].foregroundColor = .blue
        }
        return string
    }
    
    func formatFromStorage(date: Date, isRelative: Bool) -> String {
        let formatter = DateFormatters.dateFormatter
        formatter.dateStyle = DateFormatter.Style(rawValue: UInt(appStorage.dateFormat))!
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = isRelative
        let string = formatter.string(from: date)
        return string
    }
    
    func dateFormats() -> [String: UInt] {
        let formatter = DateFormatters.dateFormatter
        let allCases = [DateFormatter.Style.short, .medium, .full, .long]
        var combos: [String: UInt] = [:]
        for dateStyle in allCases {
            //            for timeStyle in allCases {
            formatter.dateStyle = dateStyle
            formatter.timeStyle = .none
            let string = formatter.string(from: .now)
            combos[string] = dateStyle.rawValue
        }
        return combos
    }
}
//
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(sheetType: Binding<SheetType?>.constant(.settings))
            .environmentObject(UserDefaultStorage.init())
    }
}

extension DateFormatter.Style {
    func toExample(date: Date = .now) -> String {
        let formatter = DateFormatters.dateFormatter
        formatter.dateStyle = self
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = false
        let string = formatter.string(from: date)
        return string
    }
    func relativeExample(date: Date = .now) -> String {
        let formatter = DateFormatters.dateFormatter
        formatter.dateStyle = self
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        let string = formatter.string(from: date)
        return string
    }
}
