import FeedKit
import Foundation
import MoraeCore

enum FeedParsingError: Error, Equatable, Sendable {
    case unsupportedFormat
}

struct FeedMetadataParser: Sendable {
    func parseRSS(
        data: Data,
        source: FeedSource
    ) throws -> [FeedCandidate] {
        let feed: Feed
        do {
            feed = try Feed(data: data)
        } catch {
            feed = try Feed(data: sanitizedRSSDates(in: data))
        }
        guard case let .rss(rss) = feed else {
            throw FeedParsingError.unsupportedFormat
        }
        return (rss.channel?.items ?? []).compactMap { item in
            candidate(
                title: item.title,
                articleURL: item.link,
                publishedAt: item.pubDate,
                source: source
            )
        }
    }

    private func sanitizedRSSDates(in data: Data) throws -> Data {
        let document = try XMLDocument(
            data: data,
            options: [.nodePreserveAll]
        )
        for node in try document.nodes(forXPath: "//item/pubDate") {
            guard let value = node.stringValue,
                  parseRSSDate(value) == nil else {
                continue
            }
            node.detach()
        }
        return document.xmlData
    }

    private func parseRSSDate(_ value: String) -> Date? {
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm zzz",
            "d MMM yyyy HH:mm:ss zzz",
            "d MMM yyyy HH:mm zzz",
            "EEE, dd MMM yyyy, HH:mm:ss zzz",
            "d MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss Z zzz",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(
                from: value.trimmingCharacters(in: .whitespacesAndNewlines)
            ) {
                return date
            }
        }
        return nil
    }

    private func candidate(
        title: String?,
        articleURL: String?,
        publishedAt: Date?,
        source: FeedSource
    ) -> FeedCandidate? {
        guard let title else {
            return nil
        }
        let normalizedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard (1...300).contains(normalizedTitle.count),
              !normalizedTitle.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }),
              let rawURL = articleURL?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              let articleURL = URL(string: rawURL),
              ["http", "https"].contains(articleURL.scheme?.lowercased() ?? ""),
              articleURL.host != nil else {
            return nil
        }
        return FeedCandidate(
            sourceID: source.id,
            sourceName: source.name,
            sourceURL: source.feedURL,
            articleURL: articleURL,
            title: normalizedTitle,
            publishedAt: publishedAt,
            isOfficialSource: source.isOfficial
        )
    }
}
