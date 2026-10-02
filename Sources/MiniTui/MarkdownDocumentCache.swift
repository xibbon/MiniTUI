import Foundation
import Markdown

/// Share parsed documents between components. All Markdown rendering uses the main actor.
@MainActor
final class MarkdownDocumentCache {
    final class Entry {
        let document: Document

        init(source: String) {
            document = Document(parsing: source)
        }
    }

    static let shared = MarkdownDocumentCache()
    private let documents = NSCache<NSString, Entry>()

    private init() {
        documents.countLimit = 64
    }

    func cachedDocument(for source: String) -> Entry? {
        documents.object(forKey: source as NSString)
    }

    func document(for source: String) -> Entry {
        if let cached = cachedDocument(for: source) { return cached }
        let entry = Entry(source: source)
        documents.setObject(entry, forKey: source as NSString)
        return entry
    }

    func removeAll() {
        documents.removeAllObjects()
    }
}
