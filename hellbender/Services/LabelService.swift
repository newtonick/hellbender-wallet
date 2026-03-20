import Foundation
import SwiftData

/// Handles label propagation between transactions, UTXOs, and addresses.
enum LabelService {
  /// Called after sync: for each incoming transaction whose receive address has a label,
  /// copy that label to the transaction (if unlabeled) and to its UTXOs (if unlabeled).
  static func propagateAddressLabels(
    transactions: [TransactionItem],
    utxos: [UTXOItem],
    context: ModelContext,
    walletID: UUID
  ) {
    let allLabels = fetchAllLabels(walletID: walletID, context: context)
    let addrLabels = Dictionary(
      allLabels.filter { $0.type == "addr" }.map { ($0.ref, $0.label) },
      uniquingKeysWith: { first, _ in first }
    )
    let txLabelRefs = Set(allLabels.filter { $0.type == "tx" }.map(\.ref))
    let utxoLabelRefs = Set(allLabels.filter { $0.type == "utxo" }.map(\.ref))

    var didChange = false

    for tx in transactions where tx.isIncoming {
      // Find first output address that carries a label
      guard let addrLabel = tx.outputs
        .compactMap({ addrLabels[$0.address] })
        .first(where: { !$0.isEmpty })
      else { continue }

      // Propagate to tx if it has no label yet
      if !txLabelRefs.contains(tx.id) {
        context.insert(WalletLabel(walletID: walletID, type: .tx, ref: tx.id, label: addrLabel))
        didChange = true
      }

      // Propagate to each UTXO from this tx that has no label yet
      for utxo in utxos where utxo.txid == tx.id {
        if !utxoLabelRefs.contains(utxo.id) {
          context.insert(WalletLabel(walletID: walletID, type: .utxo, ref: utxo.id, label: addrLabel))
          didChange = true
        }
      }
    }

    if didChange { try? context.save() }
  }

  /// Called after saving a receive transaction's label.
  /// - Copies the label to related UTXOs that have no label yet.
  /// - Copies the label to receive addresses from that tx that have no label yet.
  static func propagateFromTxLabel(
    txid: String,
    newLabel: String,
    transaction: TransactionItem,
    utxos: [UTXOItem],
    context: ModelContext,
    walletID: UUID
  ) {
    guard transaction.isIncoming, !newLabel.isEmpty else { return }

    let allLabels = fetchAllLabels(walletID: walletID, context: context)
    let utxoLabelRefs = Set(allLabels.filter { $0.type == "utxo" }.map(\.ref))
    let addrLabelRefs = Set(allLabels.filter { $0.type == "addr" }.map(\.ref))

    var didChange = false

    for utxo in utxos where utxo.txid == txid {
      if !utxoLabelRefs.contains(utxo.id) {
        context.insert(WalletLabel(walletID: walletID, type: .utxo, ref: utxo.id, label: newLabel))
        didChange = true
      }
    }

    for output in transaction.outputs where output.isMine {
      if !addrLabelRefs.contains(output.address) {
        context.insert(WalletLabel(walletID: walletID, type: .addr, ref: output.address, label: newLabel))
        didChange = true
      }
    }

    if didChange { try? context.save() }
  }

  /// Called after a send transaction is broadcast.
  /// Labels the change address and change UTXO as "Change From: <txLabel>".
  static func propagateChangeLabel(
    txid: String,
    txLabel: String,
    changeAddress: String,
    changeVout: UInt32,
    context: ModelContext,
    walletID: UUID
  ) {
    guard !txLabel.isEmpty, !changeAddress.isEmpty else { return }
    let changeLabel = "Change From: \(txLabel)"
    let allLabels = fetchAllLabels(walletID: walletID, context: context)
    let addrLabelRefs = Set(allLabels.filter { $0.type == "addr" }.map(\.ref))
    let utxoLabelRefs = Set(allLabels.filter { $0.type == "utxo" }.map(\.ref))

    var didChange = false

    if !addrLabelRefs.contains(changeAddress) {
      context.insert(WalletLabel(walletID: walletID, type: .addr, ref: changeAddress, label: changeLabel))
      didChange = true
    }

    let utxoRef = "\(txid):\(changeVout)"
    if !utxoLabelRefs.contains(utxoRef) {
      context.insert(WalletLabel(walletID: walletID, type: .utxo, ref: utxoRef, label: changeLabel))
      didChange = true
    }

    if didChange { try? context.save() }
  }

  // MARK: - Private

  private static func fetchAllLabels(walletID: UUID, context: ModelContext) -> [WalletLabel] {
    let descriptor = FetchDescriptor<WalletLabel>(predicate: #Predicate { $0.walletID == walletID })
    return (try? context.fetch(descriptor)) ?? []
  }
}
