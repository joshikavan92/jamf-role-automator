//
//  RoleAutomatorApp.swift
//  RoleAutomator
//
//  Created by Kavan Joshi on 6/28/25.
//

import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

class RoleAutomatorAppState: ObservableObject {
    @Published var showAbout = false
    @Published var showTips = false
}

@main
struct RoleAutomatorApp: App {
    @StateObject private var appState = RoleAutomatorAppState()
    
    #if os(macOS)
    init() {
        // Use custom app icon from provided PNG exports if available
        // Prefer high-resolution 512x512 asset
        let iconPath = "/Users/kavan.joshi/Library/CloudStorage/OneDrive-Jamf/K1 Jamf SE/Scripts/Apps - XCode/macOS/RoleAutomator/RoleAutomator/Logo/Logo_transperent/Icon Exports/Icon-iOS-Default-512x512@1x.png"
        if let image = NSImage(contentsOfFile: iconPath) {
            NSApplication.shared.applicationIconImage = image
        }
    }
    #endif
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 700)
        }
    }
}
