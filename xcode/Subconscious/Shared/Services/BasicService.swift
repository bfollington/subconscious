//
//  BasicEnvironment.swift
//  Subconscious (iOS)
//
//  Created by Gordon Brander on 5/5/21.
//
import os

/// A basic services environment for reducers that exposes a logger.
/// We may expand this to cover a few other non-destructive services.
struct BasicService {
    static let `default` = BasicService(
        log: Logger(
            subsystem: Constants.rdns,
            category: "main"
        )
    )
    
    let log: Logger
}