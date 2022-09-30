//
//  OnThisDayGeist.swift
//  Subconscious (iOS)
//
//  Created by Ben Follington on 30/9/2022.
//

import Foundation

struct ComboGeist: Geist {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    func ask(query: String) -> Story? {
        guard let entry = database.readRandomEntry() else {
            return nil
        }
        
        return Story.onThisDay(StoryOnThisDay(entry: entry, timeSince: "6mo"))
    }
}

