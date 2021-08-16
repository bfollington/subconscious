//
//  SubURL.swift
//  SubURL
//
//  Created by Gordon Brander on 8/16/21.
//

import Foundation

struct SubURL {
    static func isWikilinkURL(_ url: URL) -> Bool {
        url.scheme == "sub" && url.host == "wikilink"
    }

    static func wikilinkToURL(_ text: String) -> URL? {
        if let path = text.addingPercentEncoding(
            withAllowedCharacters: .urlHostAllowed
        ) {
            return URL(string: "sub://wikilink/\(path)")
        }
        return nil
    }

    static func urlToWikilink(_ url: URL) -> String? {
        if isWikilinkURL(url) {
            if let path = url.path.removingPercentEncoding {
                if path.hasPrefix("/") {
                    return String(path.dropFirst())
                }
                return path
            }
        }
        return nil
    }
}
