//
//  CalendarRepresentable.swift
//  CalendarRepresentable
//
//  Created by Umar Haroon on 8/22/21.
//

import Foundation
import SwiftUI
import EventKit
import EventKitUI
import SportsCalModel

struct CalendarRepresentable: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    @Environment(\.presentationMode) var presentationMode

    
    let eventStore: EKEventStore
    let event: EKEvent?
    
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let eventEditViewController = EKEventEditViewController()
        eventEditViewController.eventStore = eventStore
        if let event = event {
            eventEditViewController.event = event
        }
        eventEditViewController.editViewDelegate = context.coordinator
        return eventEditViewController
    }
    
    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {
        
    }
    
    typealias UIViewControllerType = EKEventEditViewController
    class Coordinator: NSObject, EKEventEditViewDelegate {
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            parent.presentationMode.wrappedValue.dismiss()
            
            if action != .canceled {
//                NotificationCenter.default.post(name: .event, object: nil)
                print("⚠️ event changed")
            }
        }
        
        let parent: CalendarRepresentable
        
        init(_ parent: CalendarRepresentable) {
            self.parent = parent
        }
    }
    
}
