import Foundation
import Observation

@Observable
@MainActor
final class UTXOListViewModel {
  var utxos: [UTXOItem] = []

  var totalAmount: UInt64 {
    utxos.reduce(0) { $0 + $1.amount }
  }

  private var bitcoinService: BitcoinService {
    BitcoinService.shared
  }

  func loadUTXOs() {
    utxos = bitcoinService.utxos
  }

  func address(for utxo: UTXOItem) -> String? {
    guard let tx = bitcoinService.transactions.first(where: { $0.id == utxo.txid }),
          Int(utxo.vout) < tx.outputs.count else { return nil }
    return tx.outputs[Int(utxo.vout)].address
  }

  func bestDate(for utxo: UTXOItem) -> Date? {
    guard let tx = bitcoinService.transactions.first(where: { $0.id == utxo.txid }) else { return nil }
    return tx.timestamp ?? tx.firstSeen
  }
}
