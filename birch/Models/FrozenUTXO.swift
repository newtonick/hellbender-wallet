import Foundation
import SwiftData

@Model
final class FrozenUTXO {
  var id: UUID
  var walletID: UUID
  var txid: String
  var vout: UInt32

  /// Composite key matching UTXOItem.id format
  var outpoint: String {
    "\(txid):\(vout)"
  }

  init(walletID: UUID, txid: String, vout: UInt32) {
    id = UUID()
    self.walletID = walletID
    self.txid = txid
    self.vout = vout
  }
}
