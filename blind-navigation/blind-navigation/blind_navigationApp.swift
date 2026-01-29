//
//  blind_navigationApp.swift
//  blind-navigation
//
//  Created by Rachit Mittal on 25/11/25.
//

import SwiftUI

@main
struct blind_navigationApp: App {
    init() {
        // Force console output immediately
        print("========================================")
        print("APP LAUNCHED - blind_navigationApp init")
        print("========================================")
        
        // Test basic SwiftUI
        print("SwiftUI framework loaded")
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // If you ever see a pure black screen, this confirms whether SwiftUI is rendering at all.
                Color.red.opacity(0.20)
                    .ignoresSafeArea()

                ContentView()

                VStack(spacing: 8) {
                    Text("UI Alive")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    Text("If you can't see this, the app isn't presenting SwiftUI.")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
                .zIndex(9999)
            }
            .onAppear {
                print("========================================")
                print("WindowGroup root appeared")
                print("========================================")
            }
        }
    }
}
