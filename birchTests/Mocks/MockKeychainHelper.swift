@testable import birch
import Foundation

final class MockKeychainHelper: KeychainStoring {
  nonisolated(unsafe) static var store: [String: Data] = [:]

  static func reset() {
    store.removeAll()
  }

  @discardableResult
  static func save(_ data: Data, forKey key: String) -> Bool {
    store[key] = data
    return true
  }

  static func load(forKey key: String) -> Data? {
    store[key]
  }

  static func delete(forKey key: String) {
    store.removeValue(forKey: key)
  }

  static func deleteAll() {
    store.removeAll()
  }
}
