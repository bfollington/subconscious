//
//  Database.swift
//  Subconscious (iOS)
//
//  Created by Gordon Brander on 5/20/21.
//
//  Handles reading, writing, building, and syncing files and database.

import Foundation
import Combine
import os
import OrderedCollections

//  TODO: consider moving search results and suggestions into database model
//  or else merge database model into App root.
//  We want database to be a component, so it can manage the complex lifecycle
//  aspects of migration as a component state machine. Yet most of the query
//  results themselves are stored elsewhere. This is ok, but feels awkward.

//  MARK: Actions
enum DatabaseAction {
    /// An action that results in no operation
    /// Useful for swallowing success conditions that are the result of an effect
    case noop
    /// Trigger a database migration.
    /// Does an early exit if version is up-to-date.
    /// All calls to the query interface in the environment perform these steps to ensure the
    /// schema is up-to-date before issuing a query.
    /// However it's a good idea to run this action when the app starts so that you get the expensive
    /// stuff out of the way early.
    case setup
    case setupSuccess(_ success: SQLite3Migrations.MigrationSuccess)
    /// Rebuild database if it is somehow impossible to migrate.
    /// This should not happen, but it allows us to recover if it does.
    case rebuild
    case rebuildFailure(message: String)
    /// Sync files with database
    case sync
    case syncSuccess(_ changes: [FileSync.Change])
    case syncFailure(message: String)
}

//  MARK: Model
struct DatabaseModel: Equatable {
    enum State: Equatable {
        case unknown
        case setup
        case ready
        case broken
    }
    
    var state: State = .unknown
}

//  MARK: Update
func updateDatabase(
    state: inout DatabaseModel,
    action: DatabaseAction,
    environment: DatabaseService
) -> AnyPublisher<DatabaseAction, Never> {
    switch action {
    case .noop:
        return Empty().eraseToAnyPublisher()
    case .setup:
        state.state = .setup
        return environment.migrateDatabase()
            .map({ success in DatabaseAction.setupSuccess(success) })
            .replaceError(with: DatabaseAction.rebuild)
            .eraseToAnyPublisher()
    case .setupSuccess(let success):
        state.state = .ready
        if success.from == success.to {
            environment.logger.info("Database up-to-date. No migration needed")
        } else {
            environment.logger.info(
                "Database migrated from \(success.from) to \(success.to) via \(success.migrations)"
            )
        }
        return Just(DatabaseAction.sync).eraseToAnyPublisher()
    case .rebuild:
        state.state = .broken
        environment.logger.warning(
            "Database is broken or has wrong schema. Attempting to rebuild."
        )
        return environment.deleteDatabase()
            .flatMap(environment.migrateDatabase)
            .map({ success in DatabaseAction.setupSuccess(success) })
            .catch({ error in
                Just(.rebuildFailure(message: error.localizedDescription))
            })
            .eraseToAnyPublisher()
    case .rebuildFailure(let message):
        environment.logger.critical(
            """
            Failed to rebuild database.
            
            Error:
            \(message)
            """
        )
    case .sync:
        environment.logger.log("File sync started")
        return environment.syncDatabase()
            .map({ changes in .syncSuccess(changes) })
            .catch({ error in
                Just(.syncFailure(message: error.localizedDescription))
            })
            .eraseToAnyPublisher()
    case .syncSuccess:
        environment.logger.log(
            """
            File sync finished
            """
        )
    case .syncFailure(let message):
        environment.logger.warning(
            """
            File sync failed.\t\(message)
            """
        )
    }
    return Empty().eraseToAnyPublisher()
}

//  MARK: Environment
struct DatabaseService {
    private let db: SQLite3ConnectionManager

    let logger = Logger(
        subsystem: "com.subconscious.Subconscious",
        category: "database"
    )
    let fileManager = FileManager.default
    let documentsUrl: URL
    let migrations: SQLite3Migrations

    init(
        databaseUrl: URL,
        documentsUrl: URL,
        migrations: SQLite3Migrations
    ) {
        self.db = SQLite3ConnectionManager(
            url: databaseUrl,
            mode: .readwrite
        )
        self.documentsUrl = documentsUrl
        self.migrations = migrations
    }

    func migrateDatabase() throws -> SQLite3Migrations.MigrationSuccess {
        let database = try self.db.connection()
        return try migrations.migrate(database: database)
    }
    
    func migrateDatabase() ->
        AnyPublisher<SQLite3Migrations.MigrationSuccess, Error> {
        CombineUtilities.async(
            qos: .background,
            execute: migrateDatabase
        )
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    func deleteDatabase() throws {
        db.close()
        try fileManager.removeItem(at: db.url)
    }
    
    func deleteDatabase() -> AnyPublisher<Void, Error> {
        CombineUtilities.async(
            execute: deleteDatabase
        )
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    func syncDatabase() -> AnyPublisher<[FileSync.Change], Error> {
        CombineUtilities.async(qos: .utility) {
            let fileUrls = try fileManager.contentsOfDirectory(
                at: documentsUrl,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ).withPathExtension("subtext")

            // Left = Leader (files)
            let left = try FileSync.readFileFingerprints(urls: fileUrls)

            // Right = Follower (search index)
            let right = try db.connection().execute(
                sql: "SELECT path, modified, size FROM entry"
            ).map({ row  in
                FileFingerprint(
                    url: URL(
                        fileURLWithPath: try row.get(0).unwrap(),
                        relativeTo: documentsUrl
                    ),
                    modified: try row.get(1).unwrap(),
                    size: try row.get(2).unwrap()
                )
            })
            
            let changes = FileSync.calcChanges(
                left: left,
                right: right
            ).filter({ change in change.status != .same })
            
            for change in changes {
                switch change.status {
                // .leftOnly = create.
                // .leftNewer = update.
                // .rightNewer = Follower shouldn't be ahead.
                //               Leader wins.
                // .conflict. Leader wins.
                case .leftOnly, .leftNewer, .rightNewer, .conflict:
                    if let left = change.left {
                        try writeEntryToDatabase(left.url)
                    }
                // .rightOnly = delete. Remove from search index
                case .rightOnly:
                    if let right = change.right {
                        try deleteEntryFromDatabase(right.url)
                    }
                // .same = no change. Do nothing.
                case .same:
                    break
                }
            }
            return changes
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    func readEntry(url: URL) throws -> FileEntry {
        try FileEntry(url: url)
    }

    func readEntry(url: URL) -> AnyPublisher<FileEntry, Error> {
        Result(catching: {
            try readEntry(url: url)
        }).publisher.eraseToAnyPublisher()
    }
    
    /// Write entry syncronously
    private func writeEntryToDatabase(
        fileEntry: FileEntry,
        attributes: FileFingerprint.Attributes
    ) throws {
        // Must store relative path, since absolute path of user documents
        // directory can be changed by system.
        let path = try fileEntry.url.relativizingPath(
            relativeTo: documentsUrl
        ).unwrap()

        try db.connection().execute(
            sql: """
            INSERT INTO entry (path, title, body, modified, size)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                title=excluded.title,
                body=excluded.body,
                modified=excluded.modified,
                size=excluded.size
            """,
            parameters: [
                .text(path),
                .text(fileEntry.title),
                .text(fileEntry.content),
                .date(attributes.modifiedDate),
                .integer(attributes.size)
            ]
        )
    }
    
    /// Write entry syncronously by reading it off of file system
    private func writeEntryToDatabase(_ url: URL) throws {
        let fileEntry = try FileEntry(url: url)
        let attributes = try FileFingerprint.Attributes.init(url: url).unwrap()
        try writeEntryToDatabase(
            fileEntry: fileEntry,
            attributes: attributes
        )
    }

    /// Create a new entry on the file system, and write to the database
    func createEntry(_ entry: DraftEntry) -> AnyPublisher<FileEntry, Error> {
        CombineUtilities.async {
            let fileEntry = try FileEntry(entry: entry).unwrap()
            return try writeEntry(fileEntry)
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    func writeEntry(
        _ fileEntry: FileEntry
    ) throws -> FileEntry {
        try fileEntry.write()
        // Re-read size and file modified from file system to make sure
        // what we store is exactly equal to file system.
        let attributes = try FileFingerprint.Attributes(
            url: fileEntry.url
        ).unwrap()
        try writeEntryToDatabase(
            fileEntry: fileEntry,
            attributes: attributes
        )
        return fileEntry
    }
    
    /// Write an entry to the file system, and to the database
    func writeEntry(
        _ fileEntry: FileEntry
    ) -> AnyPublisher<FileEntry, Error> {
        CombineUtilities.async {
            try writeEntry(fileEntry)
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
    
    private func deleteEntryFromDatabase(_ url: URL) throws {
        try db.connection().execute(
            sql: """
            DELETE FROM entry WHERE path = ?
            """,
            parameters: [
                .text(url.lastPathComponent)
            ]
        )
    }

    /// Remove entry from file system and database
    func deleteEntry(_ url: URL) -> AnyPublisher<URL, Error> {
        CombineUtilities.async {
            try fileManager.removeItem(at: url)
            try deleteEntryFromDatabase(url)
            return url
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    private static func collateSuggestions(
        query: String,
        results: [String],
        queries: [String]
    ) -> Suggestions {
        let resultPairs = results.map({ string in
            (string.toSlug(), string)
        })

        let queryPairs = queries.map({ string in
            (string.toSlug(), string)
        })

        let resultDict = OrderedDictionary(
            resultPairs,
            uniquingKeysWith: { (first, _) in first }
        )

        let querySlug = query.toSlug()

        var queryDict = OrderedDictionary(
            queryPairs,
            uniquingKeysWith: { (first, _) in first }
        )

        // Remove queries that are also in results
        queryDict.removeKeys(keys: resultDict.keys.elements)
        // Remove query itself. We always place the literal query as the first result.
        queryDict.removeValue(forKey: querySlug)

        // Create a mutable array we can use for suggestions.
        var suggestions: [Suggestion] = []

        // If we have a user query, and the query is not in results,
        // then append it to top.
        if !query.isWhitespace && resultDict[query.toSlug()] == nil {
            suggestions.append(
                .query(.init(query: query))
            )
        }

        for query in resultDict.values {
            suggestions.append(.result(.init(query: query)))
        }

        for query in queryDict.values {
            suggestions.append(.query(.init(query: query)))
        }

        return Suggestions(
            query: query,
            suggestions: suggestions
        )
    }
    
    func searchSuggestionsForZeroQuery() -> AnyPublisher<Suggestions, Error> {
        CombineUtilities.async(qos: .userInitiated) {
            let results: [String] = try db.connection().execute(
                sql: """
                SELECT DISTINCT title
                FROM entry_search
                ORDER BY modified DESC
                LIMIT 5
                """
            ).compactMap({ row in row.get(0) })

            let queries: [String] = try db.connection().execute(
                sql: """
                SELECT DISTINCT search_history.query
                FROM search_history
                ORDER BY search_history.created DESC
                LIMIT 5
                """
            ).compactMap({ row in
                row.get(0)
            })

            return Self.collateSuggestions(
                query: "",
                results: results,
                queries: queries
            )
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    func searchSuggestionsForQuery(
        _ query: String
    ) -> AnyPublisher<Suggestions, Error> {
        CombineUtilities.async(qos: .userInitiated) {
            guard !query.isWhitespace else {
                return Suggestions(query: query)
            }

            let results: [String] = try db.connection().execute(
                sql: """
                SELECT DISTINCT title
                FROM entry_search
                WHERE entry_search.title MATCH ?
                ORDER BY rank
                LIMIT 5
                """,
                parameters: [
                    SQLite3Connection.Value.prefixQueryFTS5(query)
                ]
            ).compactMap({ row in
                row.get(0)
            })

            let queries: [String] = try db.connection().execute(
                sql: """
                SELECT DISTINCT query
                FROM search_history
                WHERE query LIKE ?
                ORDER BY created DESC
                LIMIT 3
                """,
                parameters: [
                    SQLite3Connection.Value.prefixQueryLike(query)
                ]
            ).compactMap({ row in
                row.get(0)
            })

            return Self.collateSuggestions(
                query: query,
                results: results,
                queries: queries
            )
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    /// Fetch search suggestions
    /// A whitespace query string will fetch zero-query suggestions.
    func searchSuggestions(
        _ query: String
    ) -> AnyPublisher<Suggestions, Error> {
        if query.isWhitespace {
            return searchSuggestionsForZeroQuery()
        } else {
            return searchSuggestionsForQuery(query)
        }
    }

    /// Fetch title suggestions
    /// Currently, this does the same thing as `suggest`, but in future we may differentiate their
    /// behavior.
    func searchTitleSuggestions(
        _ query: String
    ) -> AnyPublisher<Suggestions, Error> {
        return searchSuggestions(query)
    }

    /// Log a search query in search history db
    func insertSearchHistory(query: String) -> AnyPublisher<String, Error> {
        CombineUtilities.async(qos: .background) {
            guard !query.isWhitespace else {
                return query
            }

            // Log search in database, along with number of hits
            try db.connection().execute(
                sql: """
                INSERT INTO search_history (id, query, hits)
                VALUES (?, ?, (
                    SELECT count(path)
                    FROM entry_search
                    WHERE entry_search MATCH ?
                ));
                """,
                parameters: [
                    .text(UUID().uuidString),
                    .text(query),
                    .queryFTS5(query),
                ]
            )

            return query
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    func findEntriesByTitles(_ titles: [String]) throws -> [FileEntry] {
        let titlesJSON = try SQLite3Connection.Value.json(titles).unwrap()
        return try db.connection().execute(
            sql: """
            SELECT entry.path, entry.body
            FROM entry
            JOIN json_each(?) AS title
            ON like(entry.title, title.value)
            """,
            parameters: [
                titlesJSON
            ]
        ).map({ row in
            let path: String = try row.get(0).unwrap()
            let content: String = try row.get(1).unwrap()
            return FileEntry(
                url: URL(fileURLWithPath: path, relativeTo: documentsUrl),
                content: content
            )
        })
    }

    func findEntryByTitle(_ title: String) throws -> FileEntry? {
        let results: [FileEntry] = try db.connection().execute(
            sql: """
            SELECT entry.path, entry.body
            FROM entry
            WHERE entry.title LIKE ?
            LIMIT 1
            """,
            parameters: [
                .text(title)
            ]
        ).map({ row in
            let path: String = try row.get(0).unwrap()
            let content: String = try row.get(1).unwrap()
            return FileEntry(
                url: URL(fileURLWithPath: path, relativeTo: documentsUrl),
                content: content
            )
        })
        return results.first
    }
    
    /// Given a list of FileEntrys, get all documents linked to with wikilinks within that list of FileEntrys.
    func selectTranscludes(
        _ fileEntries: [FileEntry]
    ) throws -> SlugIndex<FileEntry> {
        let wikilinks = fileEntries.flatMap({ fileEntry in
            fileEntry.content.extractWikilinks()
        })
        let linked = try findEntriesByTitles(wikilinks)
        return SlugIndex(linked)
    }

    func search(query: String) -> AnyPublisher<EntryResults, Error> {
        CombineUtilities.async(qos: .userInitiated) {
            guard !query.isWhitespace else {
                return EntryResults()
            }

            let matches: [FileEntry] = try db.connection().execute(
                sql: """
                SELECT path, body
                FROM entry_search
                WHERE entry_search MATCH ?
                AND rank = 'bm25(0.0, 10.0, 1.0, 0.0, 0.0)'
                ORDER BY rank
                LIMIT 200
                """,
                parameters: [
                    .queryFTS5(query)
                ]
            ).map({ row in
                let path: String = try row.get(0).unwrap()
                let content: String = try row.get(1).unwrap()
                let url = documentsUrl.appendingPathComponent(path)
                return FileEntry(
                    url: url,
                    content: content
                )
            })

            let entry = try findEntryByTitle(query)

            let backlinks: [FileEntry]
            if let entry = entry {
                // If we have an entry, filter it out of the results
                backlinks = matches.filter({ fileEntry in
                    fileEntry.id != entry.id
                })
            } else {
                backlinks = matches
            }

            return EntryResults(
                entry: entry,
                backlinks: backlinks
            )
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
}
