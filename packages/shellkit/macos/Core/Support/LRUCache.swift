import Foundation

/// Small thread-safe LRU cache.
public final class LRUCache<Key: Hashable, Value> {
  private var values: [Key: Value] = [:]
  private var order: [Key] = []
  private let capacity: Int
  private let lock = NSLock()

  public init(capacity: Int) {
    self.capacity = capacity
  }

  public func get(_ key: Key) -> Value? {
    lock.lock(); defer { lock.unlock() }
    guard let v = values[key] else { return nil }
    touch(key)
    return v
  }

  public func set(_ key: Key, _ value: Value) {
    lock.lock(); defer { lock.unlock() }
    values[key] = value
    touch(key)
    while order.count > capacity {
      let evicted = order.removeFirst()
      values.removeValue(forKey: evicted)
    }
  }

  public func remove(_ key: Key) {
    lock.lock(); defer { lock.unlock() }
    values.removeValue(forKey: key)
    order.removeAll { $0 == key }
  }

  public var count: Int {
    lock.lock(); defer { lock.unlock() }
    return values.count
  }

  public var keys: [Key] {
    lock.lock(); defer { lock.unlock() }
    return order
  }

  private func touch(_ key: Key) {
    order.removeAll { $0 == key }
    order.append(key)
  }
}
