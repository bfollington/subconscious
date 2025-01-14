//
//  DataService.swift
//  Subconscious
//
//  Created by Gordon Brander on 1/22/23.
//
import Foundation
import Combine
import os

enum DataServiceError: Error, LocalizedError {
    case fileExists(String)
    case memoNotFound(String)
    case defaultSphereNotFound
    case sphereExists(_ sphereIdentity: String)
    
    var errorDescription: String? {
        switch self {
        case .fileExists(let message):
            return "File exists: \(message)"
        case .memoNotFound(let message):
            return "Memo not found: \(message)"
        case .defaultSphereNotFound:
            return "Default sphere not found"
        case let .sphereExists(sphereIdentity):
            return "Sphere exists: \(sphereIdentity)"
        }
    }
}

// MARK: SERVICE
/// Wraps both database and source-of-truth store, providing data
/// access methods for the app.
struct DataService {
    var noosphere: NoosphereService
    var database: DatabaseService
    var local: HeaderSubtextMemoStore
    var logger: Logger

    init(
        noosphere: NoosphereService,
        database: DatabaseService,
        local: HeaderSubtextMemoStore
    ) {
        self.database = database
        self.noosphere = noosphere
        self.local = local
        self.logger = Logger(
            subsystem: Config.default.rdns,
            category: "DataService"
        )
    }

    /// Create a default sphere for user if needed, and persist sphere details.
    /// - Returns: SphereReceipt
    /// Will not create sphere if a sphereIdentity already appears in
    /// the user defaults.
    func createSphere(ownerKeyName: String) throws -> SphereReceipt {
        // Do not create sphere if one already exists
        if let sphereIdentity = AppDefaults.standard.sphereIdentity {
            throw DataServiceError.sphereExists(sphereIdentity)
        }
        let sphereReceipt = try noosphere.createSphere(
            ownerKeyName: ownerKeyName
        )
        // Persist sphere identity to user defaults.
        // NOTE: we do not persist the mnemonic, since it would be insecure.
        // Instead, we return the receipt so that mnemonic can be displayed
        // and discarded.
        AppDefaults.standard.sphereIdentity = sphereReceipt.identity
        AppDefaults.standard.ownerKeyName = ownerKeyName
        // Set sphere identity on NoosphereService
        noosphere.resetSphere(sphereReceipt.identity)
        return sphereReceipt
    }

    /// Sync local state to gateway
    func syncSphereWithGateway() -> AnyPublisher<String, Error> {
        CombineUtilities.async(qos: .utility) {
            try noosphere.sync()
        }
    }

    /// Migrate database off main thread, returning a publisher
    func migrateAsync() -> AnyPublisher<Int, Error> {
        CombineUtilities.async(qos: .utility) {
            try database.migrate()
        }
    }

    func rebuildAsync() -> AnyPublisher<Int, Error> {
        CombineUtilities.async(qos: .utility) {
            try database.rebuild()
        }
    }

    func syncSphereWithDatabase() throws -> String {
        let identity = try noosphere.identity()
        let version = try noosphere.version()
        let since = try? database.readMetadata(key: .sphereVersion)
        let changes = try noosphere.changes(since)
        for change in changes {
            guard let address = MemoAddress(
                formatting: change,
                audience: .public
            ) else {
                continue
            }
            let slashlink = address.slug.toSlashlink()
            // If memo does exist, write it to database
            // Sphere content is always public right now
            if let memo = try? noosphere.read(slashlink: slashlink).toMemo() {
                try database.writeMemo(
                    address,
                    memo: memo
                )
            }
            // If memo does not exist, that means change was a remove
            else {
                try database.removeMemo(address)
            }
        }
        try database.writeMetadatadata(key: .sphereIdentity, value: identity)
        try database.writeMetadatadata(key: .sphereVersion, value: version)
        return version
    }

    func syncSphereWithDatabaseAsync() -> AnyPublisher<String, Error> {
        CombineUtilities.async(qos: .utility) {
            try syncSphereWithDatabase()
        }
    }

    /// Sync file system with database.
    /// Note file system is source-of-truth (leader).
    /// Syncing will never delete files on the file system.
    func syncLocalWithDatabase() -> AnyPublisher<[FileFingerprintChange], Error> {
        CombineUtilities.async(qos: .utility) {
            // Left = Leader (files)
            let left: [FileFingerprint] = try local.list()
                .compactMap({ slug in
                    guard let info = local.info(slug) else {
                        return nil
                    }
                    return FileFingerprint(
                        slug: slug,
                        info: info
                    )
                })
            // Right = Follower (search index)
            let right = try database.listLocalMemoFingerprints()
            
            let changes = FileSync.calcChanges(
                left: left,
                right: right
            )
            .filter({ change in
                switch change {
                case .same:
                    return false
                default:
                    return true
                }
            })
            for change in changes {
                switch change {
                // .leftOnly = create.
                // .leftNewer = update.
                // .rightNewer = Follower shouldn't be ahead.
                //               Leader wins.
                // .conflict. Leader wins.
                case .leftOnly(let left), .leftNewer(let left, _), .rightNewer(let left, _), .conflict(let left, _):
                    var memo = try local.read(left.slug).unwrap()
                    // Read info from file system and set modified time
                    let info = try local.info(left.slug).unwrap()
                    memo.modified = info.modified
                    try database.writeMemo(
                        MemoAddress(slug: left.slug, audience: .local),
                        memo: memo,
                        size: info.size
                    )
                // .rightOnly = delete. Remove from search index
                case .rightOnly(let right):
                    try database.removeMemo(
                        MemoAddress(slug: right.slug, audience: .local)
                    )
                // .same = no change. Do nothing.
                case .same:
                    break
                }
            }
            return changes
        }
    }

    /// Read memo from sphere or local
    func readMemo(
        address: MemoAddress
    ) throws -> Memo {
        switch address.audience {
        case .public:
            return try noosphere
                .read(slashlink: address.slug.toSlashlink())
                .toMemo()
                .unwrap()
        case .local:
            return try local
                .read(address.slug)
                .unwrap()
        }
    }

    /// Write entry to file system and database
    /// Also sets modified header to now.
    func writeMemo(
        address: MemoAddress,
        memo: Memo
    ) throws {
        var memo = memo
        memo.modified = Date.now

        switch address.audience {
        case .public:
            let body = try memo.body.toData().unwrap()
            try noosphere.write(
                slug: address.slug.description,
                contentType: memo.contentType,
                additionalHeaders: memo.headers,
                body: body
            )
            let version = try noosphere.save()
            // Write to database
            try database.writeMemo(
                address,
                memo: memo
            )
            // Write new sphere version to database
            try database.writeMetadatadata(
                key: .sphereVersion,
                value: version
            )
            return
        case .local:
            try local.write(address.slug, value: memo)
            // Read modified/size from file system directly after writing.
            // Why: we use file system as source of truth and don't want any
            // discrepencies to sneak in (e.g. different time between write and
            // persistence on file system).
            let info = try local.info(address.slug).unwrap()
            memo.modified = info.modified
            try database.writeMemo(
                address,
                memo: memo,
                size: info.size
            )
            return
        }
    }

    func writeEntry(_ entry: MemoEntry) throws {
        try writeMemo(address: entry.address, memo: entry.contents)
    }

    func writeEntryAsync(_ entry: MemoEntry) -> AnyPublisher<Void, Error> {
        CombineUtilities.async(qos: .utility) {
            try writeEntry(entry)
        }
    }
    
    /// Delete entry from file system and database
    func deleteMemo(_ address: MemoAddress) throws {
        switch address.audience {
        case .local:
            try local.remove(address.slug)
            try database.removeMemo(address)
            return
        case .public:
            try noosphere.remove(slug: address.slug.description)
            let version = try noosphere.save()
            try database.removeMemo(address)
            try database.writeMetadatadata(key: .sphereVersion, value: version)
            return
        }
    }
    
    /// Delete entry from file system and database
    func deleteMemoAsync(_ address: MemoAddress) -> AnyPublisher<Void, Error> {
        CombineUtilities.async(qos: .background) {
            try deleteMemo(address)
        }
    }
    
    /// Update audience for memo.
    /// This moves memo from sphere to local or vise versa.
    func updateAudience(
        address: MemoAddress,
        audience: Audience
    ) throws -> MemoAddress {
        // Exit early if no change is needed
        guard address.audience != audience else {
            return address
        }
        let memo = try readMemo(address: address)
        let newAddress = address.withAudience(audience)
        try writeMemo(
            address: newAddress,
            memo: memo
        )
        try deleteMemo(address)
        return newAddress
    }

    /// Update audience for memo.
    /// This moves memo from sphere to local or vise versa.
    func updateAudienceAsync(
        address: MemoAddress,
        audience: Audience
    ) -> AnyPublisher<MemoAddress, Error> {
        CombineUtilities.async {
            return try updateAudience(address: address, audience: audience)
        }
    }

    /// Move entry to a new location, updating file system and database.
    func moveEntry(from: EntryLink, to: EntryLink) throws {
        guard from.address.slug != to.address.slug else {
            throw DataServiceError.fileExists(to.address.slug.description)
        }
        guard !self.exists(to.address) else {
            throw DataServiceError.fileExists(to.address.slug.description)
        }
        let fromMemo = try readMemo(address: from.address)
        // Make a copy representing new location and set new title and slug
        var toMemo = fromMemo
        // Update title
        toMemo.title = to.title
        // Write to new destination
        try writeMemo(address: to.address, memo: toMemo)
        // ...Then delete old entry
        try deleteMemo(from.address)
    }
    
    /// Move entry to a new location, updating file system and database.
    /// - Returns a combine publisher
    func moveEntryAsync(
        from: EntryLink,
        to: EntryLink
    ) -> AnyPublisher<Void, Error> {
        CombineUtilities.async {
            try moveEntry(from: from, to: to)
        }
    }
    
    /// Merge child entry into parent entry.
    /// - Appends `child` to `parent`
    /// - Writes the combined content to `parent`
    /// - Deletes `child`
    func mergeEntry(
        parent: EntryLink,
        child: EntryLink
    ) throws {
        let childMemo = try readMemo(address: child.address)
        let parentMemo = try readMemo(address: parent.address)
        let mergedMemo = parentMemo.merge(childMemo)
        //  First write the merged file to "to" location
        try writeMemo(address: parent.address, memo: mergedMemo)
        //  Then delete child entry *afterwards*.
        //  We do this last to avoid data loss in case of write errors.
        try deleteMemo(child.address)
    }
    
    /// Merge child entry into parent entry.
    /// - Appends `child` to `parent`
    /// - Writes the combined content to `parent`
    /// - Deletes `child`
    /// - Returns combine publisher
    func mergeEntryAsync(
        parent: EntryLink,
        child: EntryLink
    ) -> AnyPublisher<Void, Error> {
        CombineUtilities.async {
            try mergeEntry(parent: parent, child: child)
        }
    }
    
    /// Update the title of an entry, without changing its slug
    func retitleEntry(
        address: MemoAddress,
        title: String
    ) throws {
        var memo = try readMemo(address: address)
        memo.title = title
        try writeMemo(address: address, memo: memo)
    }
    
    /// Change title header of entry, without moving it.
    /// - Returns combine publisher
    func retitleEntryAsync(
        address: MemoAddress,
        title: String
    ) -> AnyPublisher<Void, Error> {
        CombineUtilities.async {
            try retitleEntry(address: address, title: title)
        }
    }
    
    func listRecentMemos() -> AnyPublisher<[EntryStub], Error> {
        CombineUtilities.async(qos: .default) {
            database.listRecentMemos()
        }
    }

    func countMemos() throws -> Int {
        return try database.countMemos().unwrap()
    }

    /// Count all entries
    func countMemos() -> AnyPublisher<Int, Error> {
        CombineUtilities.async(qos: .userInteractive) {
            try countMemos()
        }
    }

    func searchSuggestions(
        query: String
    ) -> AnyPublisher<[Suggestion], Error> {
        CombineUtilities.async(qos: .userInitiated) {
            try database.searchSuggestions(query: query)
        }
    }

    /// Fetch search suggestions
    /// A whitespace query string will fetch zero-query suggestions.
    func searchLinkSuggestions(
        query: String,
        omitting invalidSuggestions: Set<MemoAddress> = Set(),
        fallback: [LinkSuggestion] = []
    ) -> AnyPublisher<[LinkSuggestion], Error> {
        CombineUtilities.async(qos: .userInitiated) {
            return database.searchLinkSuggestions(
                query: query,
                omitting: invalidSuggestions,
                fallback: fallback
            )
        }
    }
    
    func searchRenameSuggestions(
        query: String,
        current: EntryLink
    ) -> AnyPublisher<[RenameSuggestion], Error> {
        CombineUtilities.async(qos: .userInitiated) {
            try database.searchRenameSuggestions(
                query: query,
                current: current
            )
        }
    }

    /// Log a search query in search history db
    func createSearchHistoryItem(query: String) -> AnyPublisher<String, Error> {
        CombineUtilities.async(qos: .utility) {
            database.createSearchHistoryItem(query: query)
        }
    }
    
    /// Check if a given address exists
    func exists(_ address: MemoAddress) -> Bool {
        switch address.audience {
        case .public:
            let version = noosphere.getFileVersion(
                slashlink: address.slug.toSlashlink()
            )
            return version != nil
        case .local:
            let info = local.info(address.slug)
            return info != nil
        }
    }

    /// Given a slug, get back a resolved MemoAddress
    /// If there is public content, that will be returned.
    /// Otherwise, if there is local content, that will be returned.
    func findAddress(
        slug: Slug
    ) -> MemoAddress? {
        // If slug exists in default sphere, return that.
        if noosphere.getFileVersion(slashlink: slug.toSlashlink()) != nil {
            return MemoAddress(slug: slug, audience: .public)
        }
        // Otherwise if slug exists on local, return that.
        if local.info(slug) != nil {
            return MemoAddress(slug: slug, audience: .local)
        }
        return nil
    }

    func readDetail(
        address: MemoAddress,
        title: String,
        fallback: String
    ) throws -> EntryDetail {
        let backlinks = database.readEntryBacklinks(slug: address.slug)

        let draft = EntryDetail(
            saveState: .draft,
            entry: Entry(
                address: address,
                contents: Memo(
                    contentType: ContentType.subtext.rawValue,
                    created: Date.now,
                    modified: Date.now,
                    title: title,
                    fileExtension: ContentType.subtext.fileExtension,
                    additionalHeaders: [],
                    body: fallback
                )
            )
        )

        let slashlink = address.slug.toSlashlink()
        switch address.audience {
        case .public:
            do {
                let memo = try noosphere.read(slashlink: slashlink)
                    .toMemo()
                    .unwrap()
                return EntryDetail(
                    saveState: .saved,
                    entry: Entry(
                        address: address,
                        contents: memo
                    ),
                    backlinks: backlinks
                )
            } catch SphereFSError.fileDoesNotExist(let slashlink) {
                logger.debug("Sphere file does not exist: \(slashlink). Returning new draft.")
                return draft
            }
        case .local:
            // Retreive top entry from file system to ensure it is fresh.
            // If no file exists, return a draft, using fallback for title.
            guard let memo = local.read(address.slug) else {
                logger.debug("Local file does not exist: \(slashlink). Returning new draft.")
                return draft
            }
            // Return entry
            return EntryDetail(
                saveState: .saved,
                entry: Entry(
                    address: address,
                    contents: memo
                ),
                backlinks: backlinks
            )
        }
    }

    /// Get memo and backlinks from slug, using string as a fallback.
    /// We trust caller to slugify the string, if necessary.
    /// Allowing any string allows us to retreive files that don't have a
    /// clean slug.
    func readDetailAsync(
        address: MemoAddress,
        title: String,
        fallback: String
    ) -> AnyPublisher<EntryDetail, Error> {
        CombineUtilities.async(qos: .utility) {
            try readDetail(address: address, title: title, fallback: fallback)
        }
    }
    
    /// Choose a random entry and publish slug
    func readRandomEntryLink() throws -> EntryLink {
        guard let link = database.readRandomEntryLink() else {
            throw DatabaseServiceError.randomEntryFailed
        }
        return link
    }

    /// Choose a random entry and publish slug
    func readRandomEntryLinkAsync() -> AnyPublisher<EntryLink, Error> {
        CombineUtilities.async(qos: .default) {
            try readRandomEntryLink()
        }
    }
}
