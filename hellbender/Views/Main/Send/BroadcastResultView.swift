import SwiftData
import SwiftUI

struct BroadcastResultView: View {
  @Bindable var viewModel: SendViewModel
  @Binding var selectedTab: Int
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      if !viewModel.broadcastTxid.isEmpty {
        // Success state
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 64))
          .foregroundStyle(Color.hbSuccess)

        Text("Transaction Broadcast")
          .font(.hbDisplay(24))
          .foregroundStyle(Color.hbTextPrimary)

        VStack(spacing: 8) {
          Text("Transaction ID")
            .font(.hbLabel())
            .foregroundStyle(Color.hbTextSecondary)

          Text(viewModel.broadcastTxid)
            .font(.hbMono(11))
            .foregroundStyle(Color.hbTextPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

          Button(action: {
            UIPasteboard.general.string = viewModel.broadcastTxid
          }) {
            Label("Copy TXID", systemImage: "doc.on.doc")
              .font(.hbBody(14))
              .foregroundStyle(Color.hbSteelBlue)
          }
        }
      } else {
        // Ready to broadcast
        SignatureProgressView(
          collected: viewModel.signaturesCollected,
          required: viewModel.requiredSignatures,
          signerStatus: viewModel.signerStatus
        )

        Image(systemName: "antenna.radiowaves.left.and.right")
          .font(.system(size: 48))
          .foregroundStyle(Color.hbBitcoinOrange)

        Text("Ready to Broadcast")
          .font(.hbDisplay(24))
          .foregroundStyle(Color.hbTextPrimary)

        Text("All required signatures have been collected")
          .font(.hbBody(14))
          .foregroundStyle(Color.hbTextSecondary)
      }

      Spacer()

      if viewModel.broadcastTxid.isEmpty {
        Button(action: {
          Task { await viewModel.broadcast() }
        }) {
          if viewModel.isProcessing {
            ProgressView()
              .tint(.white)
              .hbPrimaryButton()
          } else {
            Text("Broadcast Transaction")
              .hbPrimaryButton()
          }
        }
        .disabled(viewModel.isProcessing)
        .padding(.horizontal, 24)

        Button(action: { viewModel.showExportQR = true }) {
          Label("Export Transaction", systemImage: "qrcode")
            .font(.hbBody(15))
            .foregroundStyle(Color.hbBitcoinOrange)
        }
      } else {
        Button(action: {
          viewModel.reset()
          selectedTab = 0
        }) {
          Text("Done")
            .hbPrimaryButton()
        }
        .padding(.horizontal, 24)
      }

      if viewModel.broadcastTxid.isEmpty {
        Button(action: {
          viewModel.currentStep = .recipients
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            viewModel.reset()
          }
        }) {
          Text("Exit")
            .font(.hbBody(16))
            .foregroundStyle(Color.hbTextSecondary)
        }
      }

      Spacer().frame(height: 32)
    }
    .onAppear {
      viewModel.finalizeTx()
    }
    .onChange(of: viewModel.broadcastTxid) {
      if !viewModel.broadcastTxid.isEmpty {
        saveRecipientLabels()
        viewModel.deleteSavedPSBT(context: modelContext)
      }
    }
    .sheet(isPresented: $viewModel.showExportQR) {
      ExportTransactionSheet(txBytes: viewModel.finalizedTxBytes)
    }
  }

  private func saveRecipientLabels() {
    guard let walletID = BitcoinService.shared.currentProfile?.id else { return }
    for recipient in viewModel.recipients {
      var trimmed = recipient.label.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      if trimmed.utf8.count > WalletLabel.maxLabelLength {
        trimmed = String(trimmed.utf8.prefix(WalletLabel.maxLabelLength))!
      }
      let address = recipient.address.trimmingCharacters(in: .whitespacesAndNewlines)
      // Save as address label — skip if one already exists
      let addrType = "addr"
      let descriptor = FetchDescriptor<WalletLabel>(predicate: #Predicate {
        $0.walletID == walletID && $0.type == addrType && $0.ref == address
      })
      if let existing = (try? modelContext.fetch(descriptor))?.first {
        existing.label = trimmed
      } else {
        modelContext.insert(WalletLabel(walletID: walletID, type: .addr, ref: address, label: trimmed))
      }
    }
    try? modelContext.save()
  }
}

struct ExportTransactionSheet: View {
  let txBytes: Data
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        Color.hbBackground.ignoresSafeArea()

        VStack(spacing: 16) {
          if !txBytes.isEmpty {
            URDisplaySheet(data: txBytes, urType: "bytes")
              .padding(5)
              .background(Color.white)
              .shadow(color: Color.hbBitcoinOrange.opacity(0.2), radius: 20)
          } else {
            Text("Transaction could not be finalized")
              .font(.hbBody())
              .foregroundStyle(Color.hbError)
          }

          Text("Scan to import the signed transaction")
            .font(.hbBody(14))
            .foregroundStyle(Color.hbTextSecondary)
            .multilineTextAlignment(.center)

          Button(action: {
            UIPasteboard.general.string = txBytes.map { String(format: "%02x", $0) }.joined()
          }) {
            Label("Copy Raw TX Hex", systemImage: "doc.on.doc")
              .font(.hbBody(14))
              .foregroundStyle(Color.hbSteelBlue)
          }
        }
        .padding(.top, 8)
      }
      .navigationTitle("Export Transaction")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .foregroundStyle(Color.hbBitcoinOrange)
        }
      }
    }
  }
}
