//
//  GitDiscoverApp.swift
//  GitDiscover
//
//  Created by Kevin MENENDEZ on 09/11/2026.
//

import SwiftUI

@main
struct GitDiscoverApp: App {
    @StateObject private var viewModel: SearchViewModel

    init() {
        _viewModel = StateObject(wrappedValue: AppCompositionRoot.makeSearchViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
