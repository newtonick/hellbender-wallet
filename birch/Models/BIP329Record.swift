import Foundation

struct BIP329Record: Codable {
  let type: String // "tx", "addr", "output", "input", "xpub"
  let ref: String
  var label: String?
  var origin: String?
  var spendable: Bool?
  var height: UInt32?
  var time: String? // ISO 8601 UTC
  var fee: UInt64?
  var value: Int64?
  var keypath: String?
  var heights: [UInt32]?

  static func parseFromJSONL(_ data: Data) -> [BIP329Record] {
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    let decoder = JSONDecoder()
    return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
      try? decoder.decode(BIP329Record.self, from: Data(line.utf8))
    }
  }

  static func encodeToJSONL(_ records: [BIP329Record]) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let lines = records.compactMap { record -> String? in
      guard let data = try? encoder.encode(record) else { return nil }
      return String(data: data, encoding: .utf8)
    }
    let joined = lines.joined(separator: "\n")
    return Data((joined.isEmpty ? joined : joined + "\n").utf8)
  }
}
