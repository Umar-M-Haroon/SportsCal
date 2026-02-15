//
//  AppLogger.swift
//  SportsCal
//
//  Central Logger definitions using Apple's os.Logger.
//  Filter in Console.app by subsystem "com.sportscal" and/or category.
//

import os

enum AppLogger {
    static let viewModel     = Logger(subsystem: "com.sportscal", category: "ViewModel")
    static let networking    = Logger(subsystem: "com.sportscal", category: "Networking")
    static let notifications = Logger(subsystem: "com.sportscal", category: "Notifications")
    static let liveActivity  = Logger(subsystem: "com.sportscal", category: "LiveActivity")
    static let calendar      = Logger(subsystem: "com.sportscal", category: "Calendar")
    static let general       = Logger(subsystem: "com.sportscal", category: "General")
    static let autoFollow    = Logger(subsystem: "com.sportscal", category: "AutoFollow")
    static let discovery     = Logger(subsystem: "com.sportscal", category: "Discovery")
    static let widget        = Logger(subsystem: "com.sportscal", category: "Widget")
}
