import Foundation
import Security

/// Generic-password items in the login keychain, one per sensitive snippet.
public struct KeychainSecretStore: SecretStore {
  public let service: String

  public init(service: String = "com.aethernative.AetherSeek.snippets") {
    self.service = service
  }

  public func read(_ id: UUID) -> String? {
    var query = baseQuery(id)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public func write(_ value: String, for id: UUID) throws {
    let data = Data(value.utf8)
    let status = SecItemUpdate(
      baseQuery(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = baseQuery(id)
      item[kSecValueData as String] = data
      item[kSecAttrLabel as String] = "AetherSeek Snippet"
      let added = SecItemAdd(item as CFDictionary, nil)
      guard added == errSecSuccess else { throw KeychainError(status: added) }
    } else if status != errSecSuccess {
      throw KeychainError(status: status)
    }
  }

  public func delete(_ id: UUID) {
    SecItemDelete(baseQuery(id) as CFDictionary)
  }

  private func baseQuery(_ id: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id.uuidString,
    ]
  }
}

public struct KeychainError: Error, CustomStringConvertible {
  public var status: OSStatus
  public var description: String {
    (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
  }
}
