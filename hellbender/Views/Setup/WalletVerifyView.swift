import SwiftUI
import URKit

struct WalletVerifyView: View {
  @Bindable var viewModel: SetupWizardViewModel
  let onComplete: () -> Void
  @State private var showDescriptorQR = false
  @State private var showDescriptorPDF = false
  @State private var copiedDescriptor = false

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        Text("Verify Wallet")
          .font(.hbDisplay(28))
          .foregroundStyle(Color.hbTextPrimary)

        // MARK: - Wallet Summary

        VStack(spacing: 16) {
          ReviewRow(label: "Name", value: viewModel.walletName.isEmpty ? "My Wallet" : viewModel.walletName)
          ReviewRow(label: "Type", value: "\(viewModel.requiredSignatures)-of-\(viewModel.totalCosigners) Multisig")
          ReviewRow(label: "Network", value: viewModel.network.displayName)
          ReviewRow(label: "Script", value: "P2WSH (Native Segwit)")
        }
        .hbCard()
        .padding(.horizontal, 24)

        // MARK: - Cosigners

        VStack(alignment: .leading, spacing: 12) {
          Text("Cosigners")
            .font(.hbHeadline)
            .foregroundStyle(Color.hbTextPrimary)

          ForEach(0 ..< viewModel.totalCosigners, id: \.self) { index in
            VStack(alignment: .leading, spacing: 6) {
              Text(viewModel.cosignerLabels[index])
                .font(.hbBody(15))
                .foregroundStyle(Color.hbTextPrimary)

              HStack(spacing: 8) {
                Text("FP:")
                  .font(.hbLabel())
                  .foregroundStyle(Color.hbTextSecondary)
                Text(viewModel.cosignerFingerprints[index])
                  .font(.hbMono(12))
                  .foregroundStyle(Color.hbBitcoinOrange)
              }

              Text(viewModel.cosignerXpubs[index])
                .font(.hbMono(10))
                .foregroundStyle(Color.hbTextSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hbSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
          }
        }
        .hbCard()
        .padding(.horizontal, 24)

        // MARK: - Back Up Your Descriptor

        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(Color.hbBitcoinOrange)
              .font(.system(size: 20))
            Text("Back Up Your Descriptor")
              .font(.hbHeadline)
              .foregroundStyle(Color.hbTextPrimary)
          }

          Text("The output descriptor is your **only** recovery path. If you lose Hellbender (phone dies, app deleted, data corrupted), the descriptor is the only thing needed to rebuild the wallet in any compatible coordinator (Sparrow, Nunchuk, etc.). Without it, you'd need to re-gather all cosigner xpubs and reconstruct the exact same configuration — which may not be possible.")
            .font(.hbBody(13))
            .foregroundStyle(Color.hbTextSecondary)

          VStack(alignment: .leading, spacing: 6) {
            BulletRow(text: "Print to PDF")
            BulletRow(text: "Import into Sparrow Wallet on another computer")
            BulletRow(text: "Save to an encrypted drive")
          }

          Button(action: { showDescriptorPDF = true }) {
            HStack(spacing: 8) {
              Image(systemName: "doc.richtext")
              Text("PDF/Print Output Descriptor")
                .font(.hbBody(15))
            }
            .foregroundStyle(Color.purple)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.purple.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
          }

          Button(action: { showDescriptorQR = true }) {
            HStack(spacing: 8) {
              Image(systemName: "qrcode.viewfinder")
              Text("Show Descriptor QR")
                .font(.hbBody(15))
            }
            .foregroundStyle(Color.hbBitcoinOrange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.hbBitcoinOrange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
          }

          Button(action: {
            UIPasteboard.general.string = viewModel.combinedDescriptor
            copiedDescriptor = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
              copiedDescriptor = false
            }
          }) {
            HStack(spacing: 8) {
              Image(systemName: copiedDescriptor ? "checkmark" : "doc.on.doc")
              Text(copiedDescriptor ? "Copied!" : "Copy Descriptor")
                .font(.hbBody(15))
            }
            .foregroundStyle(Color.hbSteelBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.hbSteelBlue.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
          }
        }
        .hbCard()
        .padding(.horizontal, 24)

        // MARK: - Verify Receive Address

        VStack(alignment: .leading, spacing: 12) {
          Label("Verify Receive Address", systemImage: "checkmark.shield")
            .font(.hbHeadline)
            .foregroundStyle(Color.hbTextPrimary)

          Text("Verifying your first receive address confirms that Hellbender built the correct output descriptor and will generate the same addresses as your cosigner devices. If the addresses don't match, funds sent to this wallet could be unspendable.")
            .font(.hbBody(13))
            .foregroundStyle(Color.hbTextSecondary)

          if let error = viewModel.addressDerivationError {
            Text(error)
              .font(.hbBody(14))
              .foregroundStyle(Color.hbError)

            Button(action: { viewModel.deriveFirstAddress() }) {
              Text("Retry")
                .font(.hbBody(14))
                .foregroundStyle(Color.hbBitcoinOrange)
            }
          } else if !viewModel.firstReceiveAddress.isEmpty {
            QRCodeView(content: viewModel.firstReceiveAddress)
              .frame(width: 200, height: 200)
              .padding(12)
              .background(Color.white)
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .frame(maxWidth: .infinity)

            viewModel.firstReceiveAddress.chunkedAddressText(font: .hbMono(12))
              .multilineTextAlignment(.center)
              .frame(maxWidth: .infinity)
              .textSelection(.enabled)

            Text("Index 0")
              .font(.hbLabel())
              .foregroundStyle(Color.hbTextSecondary)
              .frame(maxWidth: .infinity)
          }

          Text("Load the output descriptor into your hardware signer (SeedSigner, Krux, etc.) and verify this address matches the first receive address shown on the device.")
            .font(.hbBody(13))
            .foregroundStyle(Color.hbTextSecondary)
        }
        .hbCard()
        .padding(.horizontal, 24)

        // MARK: - Actions

        Button(action: onComplete) {
          Text("Create Wallet")
            .hbPrimaryButton()
        }
        .padding(.horizontal, 24)

        Button(action: { viewModel.goBack() }) {
          Text("Back")
            .font(.hbBody(16))
            .foregroundStyle(Color.hbTextSecondary)
        }
        .padding(.bottom, 32)
      }
      .padding(.top, 16)
    }
    .sheet(isPresented: $showDescriptorQR) {
      DescriptorQRSheet(descriptor: viewModel.combinedDescriptor)
    }
    .sheet(isPresented: $showDescriptorPDF) {
      DescriptorPDFView(
        walletName: viewModel.walletName.isEmpty ? "My Wallet" : viewModel.walletName,
        descriptor: viewModel.externalDescriptor
      )
    }
  }
}

// MARK: - Supporting Views

private struct ReviewRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack {
      Text(label)
        .font(.hbLabel())
        .foregroundStyle(Color.hbTextSecondary)
      Spacer()
      Text(value)
        .font(.hbBody(15))
        .foregroundStyle(Color.hbTextPrimary)
    }
  }
}

private struct DescriptorQRSheet: View {
  let descriptor: String
  let descriptorUR: UR?
  @Environment(\.dismiss) private var dismiss

  init(descriptor: String) {
    self.descriptor = descriptor
    descriptorUR = try? URService.encodeCryptoOutput(descriptor: descriptor)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color.hbBackground.ignoresSafeArea()

        VStack(spacing: 16) {
          if let ur = descriptorUR {
            URDisplaySheet(ur: ur)
              .padding(5)
              .background(Color.white)
              .shadow(color: Color.hbBitcoinOrange.opacity(0.2), radius: 20)
          } else {
            Text("Failed to encode descriptor")
              .font(.hbBody())
              .foregroundStyle(Color.hbError)
          }

          Text("Scan to import this wallet descriptor")
            .font(.hbBody(14))
            .foregroundStyle(Color.hbTextSecondary)
            .multilineTextAlignment(.center)

          Button(action: {
            UIPasteboard.general.string = descriptor
          }) {
            Label("Copy Descriptor", systemImage: "doc.on.doc")
              .font(.hbBody(14))
              .foregroundStyle(Color.hbSteelBlue)
          }
        }
        .padding(.top, 8)
      }
      .navigationTitle("Wallet Descriptor")
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

private struct BulletRow: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text("\u{2022}")
        .font(.hbBody(13))
        .foregroundStyle(Color.hbBitcoinOrange)
      Text(text)
        .font(.hbBody(13))
        .foregroundStyle(Color.hbTextSecondary)
    }
  }
}
