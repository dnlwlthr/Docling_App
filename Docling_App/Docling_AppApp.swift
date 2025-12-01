//
//  Docling_AppApp.swift
//  Docling_App
//
//  App entry point with backend lifecycle management.
//

import SwiftUI
import AppKit

/// Application delegate to handle app termination.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        print("App terminating - stopping backend...")
        BackendManager.shared.stop()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct Docling_AppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    private let backendManager = BackendManager.shared
    
    init() {
        // Start backend process early on app launch
        print("App launching - starting backend...")
        backendManager.startIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
        }
    }
    
    /// Handle scene phase changes to manage backend lifecycle.
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background, .inactive:
            // App is going to background or becoming inactive
            // We keep the backend running in case user switches back
            print("App entering background/inactive - keeping backend running")
            
        case .active:
            // App became active - check backend health
            print("App became active - checking backend health")
            backendManager.checkHealth()
            
        @unknown default:
            break
        }
    }
}
