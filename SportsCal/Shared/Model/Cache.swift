//
//  Cache.swift
//  FF-Take-Home-Project
//
//  Created by Umar Haroon on 6/14/22.
//

import Foundation

final class Cache<Key: Hashable, Value> {
    private let wrapped = NSCache<WrappedKey, Entry>()
    private let dateProvider: () -> Date
    private let entryLifetime: TimeInterval
    private let keyTracker = KeyTracker()
    
    init(dateProvider: @escaping() -> Date = Date.init, entryLifetime: TimeInterval = 12 * 60 * 60, maxEntryCountLimit: Int = 10) {
        self.dateProvider = dateProvider
        self.entryLifetime = entryLifetime
        wrapped.countLimit = maxEntryCountLimit
        wrapped.delegate = keyTracker
    }
    
    func insert(_ value: Value, for key: Key) {
        let date = dateProvider().addingTimeInterval(entryLifetime)
        let entry = Entry(key: key, value: value, expirationDate: date)
        insert(entry)
    }
    func value(for key: Key) -> Value? {
        entry(forKey: key)?.value
    }
    
    func removeValue(for key: Key) {
        wrapped.removeObject(forKey: WrappedKey(key))
    }
    subscript(key: Key) -> Value? {
        get {
            return value(for: key)
        }
        set {
            guard let value = newValue else {
                removeValue(for: key)
                return
            }
            
            insert(value, for: key)
        }
    }
    
    func deleteAll() {
        for key in keyTracker.keys {
            removeValue(for: key)
        }
    }
}
private extension Cache {
    final class WrappedKey: NSObject {
        let key: Key
        
        init(_ key: Key) { self.key = key }
        
        override var hash: Int { return key.hashValue }
        
        override func isEqual(_ object: Any?) -> Bool {
            guard let value = object as? WrappedKey else { return false }
            
            return value.key == key
        }
    }
    
    final class Entry {
        let key: Key
        let value: Value
        let expirationDate: Date
        
        init(key: Key, value: Value, expirationDate: Date) {
            self.key = key
            self.value = value
            self.expirationDate = expirationDate
        }
    }
}
private extension Cache {
    final class KeyTracker: NSObject, NSCacheDelegate {
        var keys = Set<Key>()
        
        func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
            guard let entry = obj as? Entry else { return }
            keys.remove(entry.key)
        }
    }
}
extension Cache.Entry: Codable where Key: Codable, Value: Codable {}
extension Cache: Codable where Key: Codable, Value: Codable {
    convenience init(from decoder: Decoder) throws {
        self.init()
        
        let container = try decoder.singleValueContainer()
        let entries = try container.decode([Entry].self)
        entries.forEach(insert)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(keyTracker.keys.map(entry))
    }
}
extension Cache where Key: Codable, Value: Codable {
    func saveToDisk(with name: String, using fileManager: FileManager = .default) throws {
        guard let folder = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let fileURL = folder.appendingPathComponent(name + ".cache")
        let data = try JSONEncoder().encode(self)
        try data.write(to: fileURL)
    }
}

extension Cache where Key: Codable & Sendable, Value: Codable & Sendable {
    /// Persists a single entry without ever touching the main thread.
    ///
    /// `saveToDisk` JSON-encodes the whole cache inline. For the `/schedules` snapshot
    /// that is a multi-megabyte `LiveScore`, and every call site was on the main actor —
    /// it showed up in Sentry as multi-second `JSONWriter.serializeObject` app hangs
    /// straight after a schedule fetch. The entry is rebuilt inside a detached task so
    /// the encode and the file write both run on the cooperative pool. Callers keep
    /// their in-memory `insert` (which is cheap) and use this for the disk half.
    ///
    /// Fire-and-forget: a failed cache write is recoverable (the next fetch rewrites
    /// it), so errors are logged rather than propagated.
    static func writeToDiskDetached(value: Value, for key: Key, name: String, entryLifetime: TimeInterval = 12 * 60 * 60) {
        Task.detached(priority: .utility) {
            do {
                let cache = Cache<Key, Value>(entryLifetime: entryLifetime)
                cache.insert(value, for: key)
                try cache.saveToDisk(with: name)
            } catch {
                AppLogger.viewModel.error("Detached cache write failed for \(name): \(error.localizedDescription)")
            }
        }
    }
}
private extension Cache {
    func entry(forKey key: Key) -> Entry? {
        guard let entry = wrapped.object(forKey: WrappedKey(key)) else {
            return nil
        }
        
        guard dateProvider() < entry.expirationDate else {
            removeValue(for: key)
            return nil
        }
        
        return entry
    }
    
    func insert(_ entry: Entry) {
        wrapped.setObject(entry, forKey: WrappedKey(entry.key))
        keyTracker.keys.insert(entry.key)
    }
}
