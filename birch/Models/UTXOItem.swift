import Foundation

struct UTXOItem: Identifiable, Equatable {
  let txid: String
  let vout: UInt32
  let amount: UInt64 // sats
  let isConfirmed: Bool
  let keychain: KeychainKind
  let derivationIndex: UInt32

  var id: String {
    "\(txid):\(vout)"
  }

  var formattedAmount: String {
    if amount >= 100_000_000 {
      let btc = Double(amount) / 100_000_000.0
      return String(format: "%.8f BTC", btc)
    }
    return "\(amount) sats"
  }

  enum KeychainKind: String {
    case external
    case `internal`
  }
}
