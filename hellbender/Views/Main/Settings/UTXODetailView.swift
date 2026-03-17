import SwiftData
import SwiftUI

struct UTXODetailView: View {
  let utxo: UTXOItem
  @Environment(\.modelContext) private var modelContext
  @Query private var frozenUTXOs: [FrozenUTXO]
  @Query private var walletLabels: [WalletLabel]
  @AppStorage(Constants.denominationKey) private var denomination: String = "sats"
  @AppStorage(Constants.fiatEnabledKey) private var fiatEnabled = false
  @AppStorage(Constants.fiatPrimaryKey) private var fiatPrimary = false

  private var service: BitcoinService {
    BitcoinService.shared
  }

  private var parentTransaction: TransactionItem? {
    service.transactions.first { $0.id == utxo.txid }
  }

  private var outputAddress: String? {
    guard let tx = parentTransaction,
          Int(utxo.vout) < tx.outputs.count else { return nil }
    return tx.outputs[Int(utxo.vout)].address
  }

  private var isFrozen: Bool {
    guard let walletID = service.currentProfile?.id else { return false }
    return frozenUTXOs.contains { $0.walletID == walletID && $0.outpoint == utxo.id }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        // Amount header
        VStack(spacing: 8) {
          Image(systemName: isFrozen ? "snowflake" : "bitcoinsign.circle.fill")
            .font(.system(size: 44))
            .foregroundStyle(isFrozen ? Color.hbSteelBlue : Color.hbBitcoinOrange)

          if fiatEnabled, fiatPrimary, let fiatStr = FiatPriceService.shared.formattedSatsToFiat(utxo.amount) {
            Text(fiatStr)
              .font(.hbAmountMedium)
              .foregroundStyle(Color.hbTextPrimary)
            Text(utxo.amount.formattedSats)
              .font(.hbBody(14))
              .foregroundStyle(Color.hbTextSecondary)
          } else {
            Text(utxo.amount.formattedSats)
              .font(.hbAmountMedium)
              .foregroundStyle(Color.hbTextPrimary)
            if fiatEnabled, let fiatStr = FiatPriceService.shared.formattedSatsToFiat(utxo.amount) {
              Text(fiatStr)
                .font(.hbBody(14))
                .foregroundStyle(Color.hbTextSecondary)
            }
          }

          HStack(spacing: 8) {
            if isFrozen {
              Text("Frozen")
                .font(.hbLabel(11))
                .foregroundStyle(Color.hbSteelBlue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.hbSteelBlue.opacity(0.15))
                .clipShape(Capsule())
            }

            Text(utxo.isConfirmed ? "Confirmed" : "Unconfirmed")
              .font(.hbLabel(11))
              .foregroundStyle(utxo.isConfirmed ? Color.hbSuccess : Color.hbBitcoinOrange)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background((utxo.isConfirmed ? Color.hbSuccess : Color.hbBitcoinOrange).opacity(0.15))
              .clipShape(Capsule())
          }
        }
        .onTapGesture(count: 2) {
          if fiatEnabled { fiatPrimary.toggle() }
        }
        .padding(.top, 8)

        // Output details
        VStack(spacing: 12) {
          if let address = outputAddress {
            VStack(alignment: .leading, spacing: 6) {
              Text("Address")
                .font(.hbLabel())
                .foregroundStyle(Color.hbTextSecondary)

              HStack(alignment: .top, spacing: 8) {
                Text(address)
                  .font(.hbMono(12))
                  .foregroundStyle(Color.hbTextPrimary)
                  .textSelection(.enabled)

                Spacer()

                Button(action: {
                  UIPasteboard.general.string = address
                }) {
                  Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.hbSteelBlue)
                }

                if let network = service.currentNetwork,
                   let url = network.explorerAddressURL(address: address, customHost: service.currentProfile?.blockExplorerHost)
                {
                  Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                      .font(.system(size: 14))
                      .foregroundStyle(Color.hbSteelBlue)
                  }
                }
              }

              if let addrLabel = addressLabel(for: address), !addrLabel.isEmpty {
                HStack(spacing: 4) {
                  Image(systemName: "tag.fill")
                    .font(.system(size: 10))
                  Text(addrLabel)
                    .font(.hbBody(12))
                }
                .foregroundStyle(Color.hbSteelBlue)
              }
            }

            Divider().overlay(Color.hbBorder)
          }

          DetailRow(label: "Amount", value: utxo.amount.formattedSats)

          DetailRow(label: "Output Index", value: "\(utxo.vout)")

          DetailRow(label: "Type", value: utxo.keychain == .external ? "Receive" : "Change")

          if let tx = parentTransaction {
            if let blockHeight = tx.blockHeight {
              DetailRow(label: "Block Height", value: "\(blockHeight)")
            }

            if let timestamp = tx.timestamp {
              DetailRow(label: "Timestamp", value: timestamp.longFormatString)
            } else if let firstSeen = tx.firstSeen {
              DetailRow(label: "First Seen", value: firstSeen.longFormatString)
            }

            DetailRow(label: "Confirmations",
                      value: tx.confirmations >= 6 ? "6+" : "\(tx.confirmations)")
          }
        }
        .hbCard()

        // Outpoint
        VStack(alignment: .leading, spacing: 6) {
          Text("Outpoint")
            .font(.hbLabel())
            .foregroundStyle(Color.hbTextSecondary)

          HStack(alignment: .top, spacing: 8) {
            Text(utxo.id)
              .font(.hbMono(11))
              .foregroundStyle(Color.hbTextPrimary)
              .textSelection(.enabled)

            Spacer()

            Button(action: {
              UIPasteboard.general.string = utxo.id
            }) {
              Image(systemName: "doc.on.doc")
                .font(.system(size: 14))
                .foregroundStyle(Color.hbSteelBlue)
            }

            if let network = service.currentNetwork,
               let url = network.explorerTxURL(txid: utxo.txid, customHost: service.currentProfile?.blockExplorerHost)
            {
              Link(destination: url) {
                Image(systemName: "arrow.up.right.square")
                  .font(.system(size: 14))
                  .foregroundStyle(Color.hbSteelBlue)
              }
            }
          }
        }
        .hbCard()

        // Freeze / Unfreeze action
        Button(action: toggleFreeze) {
          HStack(spacing: 8) {
            Image(systemName: isFrozen ? "flame" : "snowflake")
            Text(isFrozen ? "Unfreeze UTXO" : "Freeze UTXO")
              .font(.hbBody(15))
          }
          .foregroundStyle(isFrozen ? Color.hbBitcoinOrange : Color.hbSteelBlue)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background((isFrozen ? Color.hbBitcoinOrange : Color.hbSteelBlue).opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .hbCard()
      }
      .padding(16)
    }
    .background(Color.hbBackground)
    .navigationTitle("UTXO Detail")
  }

  private func addressLabel(for address: String) -> String? {
    guard let walletID = service.currentProfile?.id else { return nil }
    return walletLabels.first(where: { $0.walletID == walletID && $0.type == "addr" && $0.ref == address })?.label
  }

  private func toggleFreeze() {
    guard let walletID = service.currentProfile?.id else { return }
    if isFrozen {
      let txid = utxo.txid
      let descriptor = FetchDescriptor<FrozenUTXO>(predicate: #Predicate {
        $0.walletID == walletID && $0.txid == txid
      })
      let outpoint = utxo.id
      if let frozen = (try? modelContext.fetch(descriptor))?.first(where: { $0.outpoint == outpoint }) {
        modelContext.delete(frozen)
        try? modelContext.save()
      }
    } else {
      modelContext.insert(FrozenUTXO(walletID: walletID, txid: utxo.txid, vout: utxo.vout))
      try? modelContext.save()
    }
  }
}

private struct DetailRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack {
      Text(label)
        .font(.hbLabel())
        .foregroundStyle(Color.hbTextSecondary)
      Spacer()
      Text(value)
        .font(.hbMono())
        .foregroundStyle(Color.hbTextPrimary)
    }
  }
}
