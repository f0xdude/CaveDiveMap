//
//  cave_mapperApp.swift
//  cave-mapper
//
//  Created by Andrey Manolov on 18.11.24.
//

import SwiftUI

@main
struct cave_mapperApp: App {
    @StateObject private var viewModel = MagnetometerViewModel()

    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
