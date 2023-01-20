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
        let folderURLs = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let fileURL = URL(string: folderURLs[0].absoluteString + name + ".cache")!
        let data = try JSONEncoder().encode(self)
        try data.write(to: fileURL)
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
