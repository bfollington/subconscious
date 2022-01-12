//
//  SubconsciousApp.swift
//  Shared
//
//  Created by Gordon Brander on 9/15/21.
//

import SwiftUI
import os

@main
struct SubconsciousApp: App {
    var body: some Scene {
        WindowGroup {
            AppView(
                store: Store(
                    state: .init(),
                    logger: Logger.init(
                        subsystem: "com.subconscious",
                        category: "store"
                    ),
                    debug: false
                )
            )
        }
    }
}
