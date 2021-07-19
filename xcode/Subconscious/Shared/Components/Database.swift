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
    case log(_ action: LoggerAction)
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
    /// Sync files with database
    case sync
    /// Perform a search with query string
    case search(_ query: String)
    case searchSuccess([TextEntry])
    case searchFailure(message: String, query: String)
    /// Log search query in search_history
    case insertSearchHistory(_ query: String)
    case insertSearchHistorySuccess(_ query: String)
    case insertSearchHistoryFailure(message: String, query: String)
    case searchAndInsertHistory(_ query: String)
    /// Perform a search over suggestions with query string
    case searchSuggestions(_ query: String)
    /// Search suggestion success with array of results
    case searchSuggestionsSuccess(_ results: SuggestionsModel)
    /// Suggest titles for entry
    case searchTitleSuggestions(_ query: String)
    /// Title suggestion success with array of results
    case searchTitleSuggestionsSuccess(_ results: SuggestionsModel)
    /// Create new entry on file system, and log in database
    case createEntry(content: String)
    case createEntrySuccess(TextEntry)
    case createEntryFailure(_ message: String)
    /// Read entry contents by URL
    case readEntry(url: URL)
    case readEntrySuccess(_ entry: TextEntry)
    case readEntryFailure(String)
    /// Update entry in file system and database.
    case updateEntry(_ entry: TextEntry)
    case updateEntrySuccess(_ entry: TextEntry)
    case updateEntryFailure(message: String, entry: TextEntry)
    /// Remove entry from file system and database
    case deleteEntry(url: URL)
    case deleteEntrySuccess(url: URL)
    case deleteEntryFailure(message: String, url: URL)
}

//  MARK: Tagging functions
func tagDatabaseLoggerAction(_ action: LoggerAction) -> DatabaseAction {
    .log(action)
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
    environment: DatabaseEnvironment
) -> AnyPublisher<DatabaseAction, Never> {
    switch action {
    case .noop:
        return Empty().eraseToAnyPublisher()
    case .log(let action):
        LoggerAction.log(
            action: action,
            environment: environment.logger
        )
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
            .replaceError(
                with: .log(.critical("Failed to rebuild database"))
            )
            .eraseToAnyPublisher()
    case .sync:
        environment.logger.log("File sync started")
        return environment.syncDatabase()
            .map({ _ in .log(.info("File sync done")) })
            .catch({ error in
                Just(
                    DatabaseAction.log(
                        .error(
                            """
                            File sync failed with error: \(error)
                            """
                        )
                    )
                )
            })
            .eraseToAnyPublisher()
    case .createEntry(let content):
        return environment.createEntry(
            content: content
        )
        .map({ entry in
            .createEntrySuccess(entry)
        })
        .catch({ error in
            Just(
                .createEntryFailure(
                    """
                    Create failed for entry.
                    Error:
                    \(error)
                    """
                )
            )
        })
        .eraseToAnyPublisher()
    case .createEntrySuccess(let entry):
        environment.logger.log("Created entry \(entry.url)")
    case .createEntryFailure(let message):
        environment.logger.warning("\(message)")
    case .readEntry(let url):
        return environment.readEntry(url: url)
            .map({ entry in
                .readEntrySuccess(entry)
            })
            .catch({ error in
                Just(
                    .readEntryFailure(
                        """
                        Failed to read entry: \(url)
                        
                        Error:
                        \(error.localizedDescription)
                        """
                    )
                )
            })
            .eraseToAnyPublisher()
    case .readEntrySuccess:
        environment.logger.warning(
            """
            DatabaseAction.readEntrySuccess
            Should be handled by parent component.
            """
        )
    case .readEntryFailure(let message):
        environment.logger.warning(
            """
            Failed to read entry:
            
            Error:
            \(message)
            """
        )
    case .updateEntry(let entry):
        return environment.writeEntry(entry)
            .map({ entry in
                .updateEntrySuccess(entry)
            })
            .catch({ error in
                Just(
                    .updateEntryFailure(
                        message: error.localizedDescription,
                        entry: entry
                    )
                )
            })
            .eraseToAnyPublisher()
    case .updateEntrySuccess(let entry):
        environment.logger.log(
            """
            Wrote entry: \(entry.url)
            """
        )
    case .updateEntryFailure(let message, let entry):
        environment.logger.warning(
            """
            Failed to write entry: \(entry.url)
            
            Error:
            \(message)
            """
        )
    case .deleteEntry(let url):
        return environment.deleteEntry(url)
            .map({ url in
                .deleteEntrySuccess(url: url)
            })
            .catch({ error in
                Just(
                    .deleteEntryFailure(
                        message: error.localizedDescription,
                        url: url
                    )
                )
            })
            .eraseToAnyPublisher()
    case .deleteEntrySuccess(let url):
        environment.logger.log(
            """
            Deleted entry: \(url)
            """
        )
    case .deleteEntryFailure(let message, let url):
        environment.logger.warning(
            """
            Failed to delete entry: \(url)
            
            Error:
            \(message)
            """
        )
    case .search(let query):
        return environment.search(query: query)
            .map({ results in DatabaseAction.searchSuccess(results) })
            .catch({ error in
                Just(
                    .searchFailure(
                        message: error.localizedDescription,
                        query: query
                    )
                )
            }).eraseToAnyPublisher()
    case .searchSuccess:
        environment.logger.warning(
            "DatabaseAction.searchSuccess should be handled by parent component"
        )
    case .searchFailure(let message, let query):
        environment.logger.warning(
            """
            Search failed for: \(query)
            
            Error:
            \(message)
            """
        )
    case .insertSearchHistory(let query):
        return environment.insertSearchHistory(query: query)
            .map({ query in
                .insertSearchHistorySuccess(query)
            })
            .catch({ error in
                Just(
                    .insertSearchHistoryFailure(
                        message: error.localizedDescription,
                        query: query
                    )
                )
            })
            .eraseToAnyPublisher()
    case .insertSearchHistorySuccess(let query):
        environment.logger.log(
            """
            Inserted search history: \(query)
            """
        )
    case .insertSearchHistoryFailure(let message, let query):
        environment.logger.warning(
            """
            Failed to insert into search history: \(query)
            
            Error:
            \(message)
            """
        )
    case .searchAndInsertHistory(let query):
        let insertSearchHistory = Just(
            DatabaseAction.insertSearchHistory(query)
        )
        let search = Just(
            DatabaseAction.search(query)
        )
        return Publishers.Merge(
            insertSearchHistory,
            search
        ).eraseToAnyPublisher()
    case .searchSuggestions(let query):
        return environment.searchSuggestions(query)
            .map({ results in .searchSuggestionsSuccess(results) })
            .catch({ error in
                Just(
                    .log(
                        .error(
                            "DatabaseAction.searchSuggestions failed with error: \(error)"
                        )
                    )
                )
            }).eraseToAnyPublisher()
    case .searchSuggestionsSuccess:
        environment.logger.warning(
            "DatabaseAction.searchSuggestionsSuccess should be handled by parent component"
        )
    case .searchTitleSuggestions(let query):
        return environment.searchTitleSuggestions(query)
            .map({ results in .searchTitleSuggestionsSuccess(results) })
            .replaceError(
                with: .log(
                    .error(
                        "DatabaseAction.searchTitleSuggestions failed"
                    )
                )
            ).eraseToAnyPublisher()
    case .searchTitleSuggestionsSuccess:
        environment.logger.warning(
            "DatabaseAction.suggestTitlesSuccess should be handled by parent component"
        )
    }
    return Empty().eraseToAnyPublisher()
}

//  MARK: Environment
struct DatabaseEnvironment {
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
    
    func migrateDatabase() ->
        Future<SQLite3Migrations.MigrationSuccess, Error> {
        Future({ promise in
            DispatchQueue.global(qos: .background).async {
                do {
                    let database = try self.db.connection()
                    let success = try migrations.migrate(database: database)
                    promise(.success(success))
                } catch {
                    promise(.failure(error))
                }
            }
        })
    }

    func deleteDatabase() -> AnyPublisher<Void, Error> {
        CombineUtilities.async(execute: {
            logger.notice("Deleting database")
            do {
                db.close()
                try fileManager.removeItem(at: db.url)
                logger.notice("Deleted database")
            } catch {
                logger.warning("Failed to delete database: \(error.localizedDescription)")
                throw error
            }
        })
    }

    func syncDatabase() -> AnyPublisher<Void, Error> {
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
            )

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
        }
    }

    func readEntry(url: URL) throws -> TextEntry {
        TextEntry(
            url: url,
            content: try String(contentsOf: url, encoding: .utf8)
        )
    }

    func readEntry(url: URL) -> AnyPublisher<TextEntry, Error> {
        Result(catching: {
            try readEntry(url: url)
        }).publisher.eraseToAnyPublisher()
    }
    
    /// Write entry syncronously
    private func writeEntryToDatabase(
        url: URL,
        title: String,
        content: String,
        modified: Date,
        size: Int
    ) throws {
        // Must store relative path, since absolute path of user documents
        // directory can be changed by system.
        let path = try url.relativizingPath(relativeTo: documentsUrl).unwrap()
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
                .text(title),
                .text(content),
                .date(modified),
                .integer(size)
            ]
        )
    }
    
    /// Write entry syncronously by reading it off of file system
    private func writeEntryToDatabase(_ url: URL) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        let title = Subtext.getTitle(markup: content)
        let attributes = try FileFingerprint.Attributes.init(url: url).unwrap()
        try writeEntryToDatabase(
            url: url,
            title: title,
            content: content,
            modified: attributes.modified,
            size: attributes.size
        )
    }

    /// Create a new entry on the file system, and write to the database
    func createEntry(
        content: String
    ) -> AnyPublisher<TextEntry, Error> {
        CombineUtilities.async {
            let title = Truncate.getFirstPseudoSentence(
                Subtext.getTitle(markup: content)
            )
            let name = Slug.toFilename(title)
            let url = try FileManager.default.findUniqueFilename(
                at: documentsUrl,
                name: name,
                ext: "subtext"
            ).unwrap()
            try content.write(to: url, atomically: true, encoding: .utf8)
            // Re-read size and file modified from file system to make sure
            // what we store is exactly equal to file system.
            let attributes = try FileFingerprint.Attributes(url: url).unwrap()
            try writeEntryToDatabase(
                url: url,
                title: title,
                content: content,
                modified: attributes.modified,
                size: attributes.size
            )
            return TextEntry(url: url, content: content)
        }
    }

    /// Write an entry to the file system, and to the database
    func writeEntry(
        _ entry: TextEntry
    ) -> AnyPublisher<TextEntry, Error> {
        CombineUtilities.async {
            let url = entry.url
            let content = entry.content
            let title = Truncate.getFirstPseudoSentence(
                Subtext.getTitle(markup: content)
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            // Re-read size and file modified from file system to make sure
            // what we store is exactly equal to file system.
            let attributes = try FileFingerprint.Attributes(url: url).unwrap()
            try writeEntryToDatabase(
                url: url,
                title: title,
                content: content,
                modified: attributes.modified,
                size: attributes.size
            )
            return entry
        }
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
    }

    func searchSuggestionsForZeroQuery() -> AnyPublisher<SuggestionsModel, Error> {
        CombineUtilities.async(qos: .userInitiated, execute: {
            let searches = try db.connection().execute(
                sql: """
                SELECT query FROM (
                    SELECT title AS query
                    FROM entry_search
                    ORDER BY modified DESC
                    LIMIT 4
                )
                UNION
                SELECT query FROM (
                    SELECT query, count(query) AS queries
                    FROM search_history
                    WHERE hits > 0
                    GROUP BY query
                    ORDER BY queries DESC
                    LIMIT 4
                )
                """
            ).compactMap({ row in
                try SearchSuggestion(query: row.get(0).unwrap())
            })

            let recent = try db.connection().execute(
                sql: """
                SELECT path, title
                FROM entry_search
                ORDER BY modified DESC
                LIMIT 3
                """
            ).compactMap({ row in
                try ActionSuggestion.edit(
                    url: URL(
                        fileURLWithPath: row.get(0).unwrap(),
                        relativeTo: documentsUrl
                    ),
                    title: row.get(1).unwrap()
                )
            })

            let entriesThatShouldExist = try db.connection().execute(
                sql: """
                SELECT query, count(query) AS queries
                FROM search_history
                WHERE hits < 1
                GROUP BY query
                ORDER BY queries DESC
                LIMIT 3
                """
            ).compactMap({ row in
                try ActionSuggestion.create(row.get(0).unwrap())
            })

            let actions = recent + entriesThatShouldExist
            
            return SuggestionsModel(
                searches: searches,
                actions: actions
            )
        })
    }

    func searchSuggestionsForQuery(
        _ query: String
    ) -> AnyPublisher<SuggestionsModel, Error> {
        CombineUtilities.async(qos: .userInitiated, execute: {
            guard !query.isWhitespace else {
                return SuggestionsModel()
            }

            let entries = try db.connection().execute(
                sql: """
                SELECT DISTINCT path, title AS query
                FROM entry_search
                WHERE entry_search.title MATCH ?
                ORDER BY rank
                LIMIT 5
                """,
                parameters: [
                    SQLite3Connection.Value.queryFTS5(query)
                ]
            )

            let history = try db.connection().execute(
                sql: """
                SELECT DISTINCT query
                FROM search_history
                WHERE query LIKE ?
                ORDER BY created DESC
                LIMIT 5
                """,
                parameters: [
                    SQLite3Connection.Value.prefixQueryLike(query)
                ]
            )

            let literalSearches = [SearchSuggestion(query: query)]

            let titleSearches: [SearchSuggestion] = entries.compactMap({ row in
                if let text: String = row.get(1) {
                    return SearchSuggestion(query: text)
                }
                return nil
            })

            let historySearches: [SearchSuggestion] = history.compactMap({ row in
                if let text: String = row.get(0) {
                    return SearchSuggestion(query: text)
                }
                return nil
            })

            let searches = Array(
                literalSearches
                    .appending(contentsOf: titleSearches)
                    .appending(contentsOf: historySearches)
                    .unique()
                    .prefix(6)
            )

            let editActions: [ActionSuggestion] = entries
                .prefix(3)
                .compactMap({ row in
                    if
                        let path: String = row.get(0),
                        let text: String = row.get(1)
                    {
                        return ActionSuggestion.edit(
                            url: URL(
                                fileURLWithPath: path, relativeTo: documentsUrl
                            ),
                            title: text
                        )
                    }
                    return nil
                })

            let createActions = [
                ActionSuggestion.create(query)
            ]

            let actions = Array(
                editActions
                    .appending(contentsOf: createActions)
                    .unique()
            )

            return SuggestionsModel(
                searches: searches,
                actions: actions
            )
        })
    }

    /// Fetch search suggestions
    /// A whitespace query string will fetch zero-query suggestions.
    func searchSuggestions(
        _ query: String
    ) -> AnyPublisher<SuggestionsModel, Error> {
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
    ) -> AnyPublisher<SuggestionsModel, Error> {
        return searchSuggestions(query)
    }

    /// Log a search query in search history db
    func insertSearchHistory(query: String) -> AnyPublisher<String, Error> {
        CombineUtilities.async(qos: .background, execute: {
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
        })
    }

    func search(query: String) -> AnyPublisher<[TextEntry], Error> {
        CombineUtilities.async(qos: .userInitiated, execute: {
            guard !query.isWhitespace else {
                return []
            }

            let docs: [TextEntry] = try db.connection().execute(
                sql: """
                SELECT path, body
                FROM entry_search
                WHERE entry_search MATCH ?
                AND rank = 'bm25(0.0, 10.0, 1.0, 0.0, 0.0)'
                ORDER BY rank
                LIMIT 25
                """,
                parameters: [
                    .queryFTS5(query)
                ]
            ).map({ row in
                let path: String = try row.get(0).unwrap()
                let content: String = try row.get(1).unwrap()
                let url = documentsUrl.appendingPathComponent(path)
                return TextEntry(
                    url: url,
                    content: content
                )
            })
            
            return docs
        })
    }
}
