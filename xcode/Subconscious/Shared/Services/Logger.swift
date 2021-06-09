//
//  Logger.swift
//  Subconscious (iOS)
//
//  Created by Gordon Brander on 6/1/21.
//  Defines logger constants

import os

let log = Logger(
    subsystem: "com.subconscious.Subconscious",
    category: "main"
)

struct SubLogger {
    static let main = Logger(
        subsystem: "com.subconscious.Subconscious",
        category: "main"
    )
    static let database = Logger(
        subsystem: "com.subconscious.Subconscious",
        category: "database"
    )
}