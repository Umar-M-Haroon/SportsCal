//
//  SubscriptionPage.swift
//  SubscriptionPage
//
//  Created by Umar Haroon on 8/15/21.
//


import SwiftUI
import SafariServices
import Purchases
struct SubscriptionPage: View {
   
    @State var showButtons: [Int] = []
    @State var didSuccessfullyPurchase: Bool = false
    @State var showAlert: Bool = false
    @State var showSF: Bool = false
    @State var isPrivacy: Bool = true
    @State var url: String = "https://komodollc.com/privacy"
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    private var sub: Purchases.Package? {
        subscriptionManager.monthlySubscription
    }
    
    private var yearlySub: Purchases.Package? {
        subscriptionManager.yearlySubscription
    }
    
   
    var body: some View {
        ZStack {
            Form {
                VStack {
                    Text("SportsCal Pro is an extra set of features that helps support development")
                        .multilineTextAlignment(.center)
                        .padding(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
                    Text("SportsCal Pro is also synced to your iCloud account, so it will sync accross devices under the same iCloud account")
                        .multilineTextAlignment(.center)
                        .padding(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                }
                .frame(minWidth: 0, idealWidth: .infinity, maxWidth: .infinity, minHeight: 0, idealHeight: 200, maxHeight: .infinity, alignment: .center)
                
                Section {
                    FeatureView(featureName: "Push Notifications", featureDescription: "Get notified when tasks are added and completed", imageName: "app.badge.fill", color: .red)
                    FeatureView(featureName: "Multiple Sports", featureDescription: "See multiple sports at once", imageName: "sportscourt.fill", color: .green)
                    FeatureView(featureName: "Filter games by time", featureDescription: "See events that are more than a week away", imageName: "clock.fill")
//                    FeatureView(featureName: "Custom App Icons", featureDescription: "Change your app icon into new styles!", imageName: "square.grid.2x2.fill", color: .blue)
                }
                
                if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                    Section {
                        if let sub = sub {
                            SubscriptionOptionView(product: sub)
                                .contentShape(Rectangle())
                        }
                        if let sub = SubscriptionManager.shared.yearlySubscription {
                            SubscriptionOptionView(product: sub)
                                .contentShape(Rectangle())
                        }
                        Button(action: {
                            SubscriptionManager.shared.restorePurchase()
                        }, label: {
                            Text("Restore Purchases")
                        })
                        .frame(minWidth: 0, idealWidth: .infinity, maxWidth: .infinity, minHeight: 0, idealHeight: 44, maxHeight: .infinity, alignment: .center)
                    }
                } else {
                    VStack {
                        Text("Thank you for purchasing SportsCal Pro!")
                            .frame(minWidth: 0, idealWidth: .infinity, maxWidth: .infinity, minHeight: 0, idealHeight: 44, maxHeight: .infinity, alignment: .center)
                        Button(action: {
                            didSuccessfullyPurchase = true
                        }, label: {
                            Text("Show Confetti")
                                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: .infinity, alignment: .center)
                                //                        .padding(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        })
                    }
                }
                Section {
                    Button("Privacy Policy") {
                        self.url = "https://komodollc.com/privacy"
                        url = "https://komodollc.com/privacy"
                        isPrivacy = true
                        showSF = true
                    }
                    Button("Terms of Use") {
                        self.url = "https://komodollc.com/Terms"
                        url = "https://komodollc.com/Terms"
                        isPrivacy = false
                        showSF = true
                    }
                }
            }
            .navigationBarTitle(Text("SportsCal Pro"))
            .alert(isPresented: $showAlert) { () -> Alert in
                Alert(title: Text("Thank you!"), message: Text("Thank you for purchasing SportsCal Pro!"), dismissButton:  Alert.Button.default(Text("Dismiss"), action: {
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 4) {
                        self.didSuccessfullyPurchase = false
                    }
                }))
            }
            .sheet(isPresented: $showSF, content: {
                if isPrivacy {
                    SFView(url: "https://komodollc.com/privacy")
                } else {
                    SFView(url: "https://komodollc.com/terms")
                }
            })
            

            if didSuccessfullyPurchase {
                Confetti()
                    .position(x: 150, y: 0)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 4) {
                            didSuccessfullyPurchase = false
                        }
                    }
            } else {
                EmptyView()
            }
            
        }
    }
}

struct SubscriptionOptionView: View {
    @State var shouldShowButton = false
    @State var product: Purchases.Package
    var body: some View {
        VStack {
            VStack(alignment: .center, spacing: 8, content: {
                HStack {
                    Text(product.product.localizedTitle)
                    Spacer()
                    HStack {
                        Button {
                            SubscriptionManager.shared.purchase(product: product)
                        } label: {
                            if product.product.subscriptionPeriod?.unit == .month {
                                Text("\(product.product.priceLocale.currencySymbol ?? "")\(product.product.price)/Month")
                            } else if product.product.subscriptionPeriod?.unit == .year {
                                Text("\(product.product.priceLocale.currencySymbol ?? "")\(product.product.price)/Year")
                            } else {
                                Text("\(product.product.price)")
                            }
                        }
                    }
                }
            })
            .frame(minWidth: 0, idealWidth: .infinity, maxWidth: .infinity, minHeight: 44, idealHeight: nil, maxHeight: 66, alignment: .center)
        }
    }
}
struct FeatureView: View {
    var featureName: String
    var featureDescription: String
    var imageName: String
    var color: Color?
    var gradient: LinearGradient?
    var body: some View {
        HStack {
            Image(systemName: imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 75, height: 75, alignment: .center)
                .cornerRadius(15)
                .padding()
                .foregroundColor(color ?? .none)
                .background(gradient)
            
            VStack {
                Text(featureName)
                    .font(.headline)
                Text(featureDescription)
            }
            .frame(minWidth: 0, idealWidth: .infinity, maxWidth: .infinity, minHeight: 0, idealHeight: 100, maxHeight: .infinity, alignment: .center)
        }
    }
}

struct SubscriptionPage_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionPage()
            .preferredColorScheme(.dark)
    }
}

struct SFView: UIViewControllerRepresentable {
    let url: String
    typealias UIViewControllerType = SFSafariViewController
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: URL(string: url)!)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        
    }
    func makeCoordinator() -> () {
        
    }
}

