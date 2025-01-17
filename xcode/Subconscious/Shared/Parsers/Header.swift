//
//  Header.swift
//  Subconscious
//
//  Created by Gordon Brander on 5/6/22.
//

import Foundation
import OrderedCollections

/// Well-known header names
enum HeaderName: String {
    case contentType = "Content-Type"
    case created = "Created"
    case modified = "Modified"
    case title = "Title"
    case fileExtension = "File-Extension"
}

/// A struct containing well-known headers
struct WellKnownHeaders: Hashable {
    var contentType: String
    var created: Date
    var modified: Date
    var title: String
    var fileExtension: String
}

extension WellKnownHeaders {
    /// Update instance from an array of additional headers.
    /// Does not update contentType, as this is a required header and
    /// we generally do not include it in the "additional" headers.
    func updating(_ additionalHeaders: [Header]) -> Self {
        var this = self
        
        if let title = additionalHeaders.get(
            first: HeaderName.title.rawValue
        ) {
            this.title = title
        }
        
        if let fileExtension = additionalHeaders.get(
            first: HeaderName.fileExtension.rawValue
        ) {
            this.fileExtension = fileExtension
        }
        
        if
            let createdString = additionalHeaders.get(
                first: HeaderName.created.rawValue
            ),
            let created = Date.from(createdString)
        {
            this.created = created
        }
        
        if
            let modifiedString = additionalHeaders.get(
                first: HeaderName.modified.rawValue
            ),
            let modified = Date.from(modifiedString)
        {
            this.modified = modified
        }
        
        return this
    }
    
    /// Get "additional" headers as an array.
    /// Does not include `Content-Type`.
    func getAdditionalHeaders() -> [Header] {
        [
            Header(name: HeaderName.title.rawValue, value: title),
            Header(
                name: HeaderName.fileExtension.rawValue,
                value: fileExtension
            ),
            Header(
                name: HeaderName.created.rawValue,
                value: created.ISO8601Format()
            ),
            Header(
                name: HeaderName.modified.rawValue,
                value: modified.ISO8601Format()
            )
        ]
    }
}

/// A header
public struct Header: Hashable, CustomStringConvertible, Codable {
    public let name: String
    public let value: String

    init(
        name: String,
        value: String
    ) {
        self.name = Self.normalizeName(name)
        self.value = Self.normalizeValue(value)
    }

    /// Parse a single header line
    /// - Returns ParseState containing header
    init?(
        _ tape: inout Tape
    ) {
        tape.save()
        // Require header to have valid name.
        guard let name = Self.parseName(&tape) else {
            tape.backtrack()
            return nil
        }
        let value = Self.parseValue(&tape)
        self.init(
            name: String(name),
            value: String(value)
        )
    }

    public var description: String {
        "\(name): \(value)\n"
    }

    /// Normalize name by capitalizing first letter of each dashed word
    /// and lowercasing the rest. E.g.
    ///
    /// content-type -> Content-Type
    /// TITLE -> Title
    ///
    /// Headers are case-insensitive. This normalization step lets us
    /// compare header keys in a case-insensitive way, and matches
    /// typical HTTP header naming conventions.
    static func normalizeName(
        _ string: String
    ) -> String {
        string
            .capitalized
            .replacingOccurrences(
                of: #"\s"#,
                with: "-",
                options: .regularExpression,
                range: nil
            )
    }

    /// Normalize header value, removing newlines.
    /// Headers are newline delimited, so you can't have newlines in them.
    static func normalizeValue(
        _ string: String
    ) -> String {
        string.replacingOccurrences(
            of: #"[\r\n]"#,
            with: " ",
            options: .regularExpression,
            range: nil
        )
    }

    static func parseName(
        _ tape: inout Tape
    ) -> Substring? {
        tape.start()
        while !tape.isExhausted() {
            let curr = tape.consume()
            if curr.isWhitespace {
                return nil
            } else if curr.isNewline {
                return nil
            } else if !curr.isASCII {
                return nil
            } else if curr == ":" {
                var name = tape.cut()
                name.removeLast()
                return name
            }
        }
        return nil
    }

    static func parseValue(
        _ tape: inout Tape
    ) -> Substring {
        Parser.discardSpaces(&tape)
        tape.start()
        while !tape.isExhausted() {
            let curr = tape.consume()
            if curr.isNewline {
                let value = tape.cut()
                return value.dropLast()
            }
        }
        return tape.cut()
    }
}

typealias Headers = Array<Header>

extension Headers {
    /// Parse headers from a substring.
    /// Handles missing headers, invalid headers, and no headers.
    /// - Returns a ParseState containing an array of headers (if any)
    init(
        _ tape: inout Tape
    ) {
        // Sniff first line. If it is empty, there are no headers.
        guard !Parser.parseEmptyLine(&tape) else {
            self.init()
            return
        }
        // Sniff first line. If it is not a valid header,
        // then return empty headers
        guard let firstHeader = Header(&tape) else {
            self.init()
            return
        }
        var headers: [Header] = [firstHeader]
        while !tape.isExhausted() {
            tape.start()
            if Parser.parseEmptyLine(&tape) {
                self.init(headers)
                return
            } else if let header = Header(&tape) {
                headers.append(header)
            } else {
                Parser.discardLine(&tape)
            }
        }
        self.init(headers)
        return
    }

    init(markup: String) {
        var tape = Tape(markup[...])
        self.init(&tape)
    }
}

extension Headers {
    /// Get headers, rendered back out as a string
    func toHeaderString() -> String {
        self
            .map({ header in String(describing: header) })
            .joined(separator: "")
            .appending("\n")
    }
    
    /// Get the value of the first header matching a particular name (if any)
    /// - Returns String?
    func get(first name: String) -> String? {
        let name = Header.normalizeName(name)
        return self
            .first(where: { header in header.name == name })
            .map({ header in header.value })
    }
    
    /// Get the value of the first header
    func get<T>(with map: (String) -> T?, first name: String) -> T? {
        get(first: name).flatMap(map)
    }
    
    /// Get values for all headers named `name`
    func get(named name: String) -> [String] {
        let name = Header.normalizeName(name)
        return self
            .filter({ header in header.name == name })
            .map({ header in header.value })
    }
    
    /// Remove all headers with a given name
    func remove(named name: String) -> Self {
        let name = Header.normalizeName(name)
        return self.filter({ header in header.name != name })
    }
    
    /// Remove duplicate headers from array, keeping only the first
    func removeDuplicates() -> Self {
        self.uniquing(with: \.name)
    }
    
    /// Merge headers.
    /// Duplicate headers from `that` are dropped.
    func merge(_ that: Headers) -> Self {
        var this = self
        this.append(contentsOf: that)
        return this.removeDuplicates()
    }

    /// Update header, either replacing the first existing header with the
    /// same key, or appending a new header to the list of headers.
    mutating func replace(_ header: Header) {
        guard let i = self.firstIndex(where: { existing in
            existing.name == header.name
        }) else {
            self.append(header)
            return
        }
        self[i] = header
    }
    
    /// Replace header.
    /// Updates value of first header with this name if it exists,
    /// or appends header with this name, if it doesn't.
    mutating func replace(name: String, value: String) {
        replace(Header(name: name, value: value))
    }
}

extension Headers {
    /// Create headers instance with required fields
    init(
        contentType: String,
        created: Date,
        modified: Date,
        title: String,
        fileExtension: String
    ) {
        self.init()
        self.replace(
            name: HeaderName.contentType.rawValue,
            value: contentType
        )
        self.replace(
            name: HeaderName.created.rawValue,
            value: String.from(created)
        )
        self.replace(
            name: HeaderName.modified.rawValue,
            value: String.from(modified)
        )
        self.replace(
            name: HeaderName.title.rawValue,
            value: title
        )
        self.replace(
            name: HeaderName.fileExtension.rawValue,
            value: fileExtension
        )
    }
}

/// A combination of parsed headers and body part
/// Parses headers and retains body portion as a substring
struct HeadersEnvelope: CustomStringConvertible {
    var headers: Headers
    var body: String
    
    init(
        headers: Headers,
        body: String
    ) {
        self.headers = headers
        self.body = body
    }
    
    init(markup: String) {
        var tape = Tape(markup[...])
        let headers = Headers(&tape)
        let body = tape.rest
        self.init(
            headers: headers,
            body: String(body)
        )
    }
    
    var description: String {
        "\(headers.toHeaderString())\(body)"
    }
}
