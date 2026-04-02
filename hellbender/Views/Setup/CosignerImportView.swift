import SwiftUI

struct CosignerImportView: View {
  @Bindable var viewModel: SetupWizardViewModel
  @State private var validationError: String?
  @State private var showScanner = false

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        Text("Import Cosigners")
          .font(.hbDisplay(28))
          .foregroundStyle(Color.hbTextPrimary)

        Text("Cosigner \(viewModel.currentCosignerIndex + 1) of \(viewModel.totalCosigners)")
          .font(.hbBody(15))
          .foregroundStyle(Color.hbTextSecondary)

        // Cosigner cards overview
        HStack(spacing: 8) {
          ForEach(0 ..< viewModel.totalCosigners, id: \.self) { index in
            CosignerSlot(
              index: index,
              isCurrent: index == viewModel.currentCosignerIndex,
              isComplete: !viewModel.cosignerXpubs[index].isEmpty
            )
          }
        }
        .padding(.horizontal, 24)

        // Current cosigner form
        VStack(spacing: 16) {
          // Label
          VStack(alignment: .leading, spacing: 6) {
            Text("Label")
              .font(.hbLabel())
              .foregroundStyle(Color.hbTextSecondary)

            TextField("Cosigner name", text: $viewModel.cosignerLabels[viewModel.currentCosignerIndex])
              .font(.hbBody())
              .padding(12)
              .background(Color.hbSurfaceElevated)
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .foregroundStyle(Color.hbTextPrimary)
          }

          // Fingerprint
          VStack(alignment: .leading, spacing: 6) {
            Text("Master Fingerprint (8 hex chars)")
              .font(.hbLabel())
              .foregroundStyle(Color.hbTextSecondary)

            TextField("e.g. 73c5da0a", text: $viewModel.cosignerFingerprints[viewModel.currentCosignerIndex])
              .font(.hbMono())
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .padding(12)
              .background(Color.hbSurfaceElevated)
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .foregroundStyle(Color.hbTextPrimary)
          }

          // Derivation path
          VStack(alignment: .leading, spacing: 6) {
            Text("Derivation Path")
              .font(.hbLabel())
              .foregroundStyle(Color.hbTextSecondary)

            TextField("m/48'/1'/0'/2'", text: $viewModel.cosignerDerivationPaths[viewModel.currentCosignerIndex])
              .font(.hbMono())
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .padding(12)
              .background(Color.hbSurfaceElevated)
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .foregroundStyle(Color.hbTextPrimary)
          }

          // Xpub
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text("Extended Public Key")
                .font(.hbLabel())
                .foregroundStyle(Color.hbTextSecondary)

              Spacer()

              Button(action: toggleXpubFormat) {
                Image(systemName: "arrow.left.arrow.right")
                  .font(.system(size: 14, weight: .bold))
                  .foregroundStyle(Color.green)
              }
              .padding(.trailing, 12)

              Button(action: pasteFromClipboard) {
                Label("Paste", systemImage: "doc.on.clipboard")
                  .font(.hbLabel())
                  .foregroundStyle(Color.hbSteelBlue)
              }
            }

            TextEditor(text: $viewModel.cosignerXpubs[viewModel.currentCosignerIndex])
              .font(.hbMono(12))
              .frame(minHeight: 80)
              .scrollContentBackground(.hidden)
              .padding(12)
              .background(Color.hbSurfaceElevated)
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .foregroundStyle(Color.hbTextPrimary)

            Button(action: { showScanner = true }) {
              Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                .font(.hbBody(15))
                .foregroundStyle(Color.hbBitcoinOrange)
            }
          }

          if let error = validationError {
            Text(error)
              .font(.hbLabel())
              .foregroundStyle(Color.hbError)
          }
        }
        .hbCard()
        .padding(.horizontal, 24)

        // Navigation
        HStack(spacing: 16) {
          Button(action: goBack) {
            Text(viewModel.currentCosignerIndex > 0 ? "Previous" : "Back")
              .font(.hbBody(16))
              .foregroundStyle(Color.hbTextSecondary)
          }

          Spacer()

          Button(action: goNext) {
            Text(viewModel.currentCosignerIndex < viewModel.totalCosigners - 1 ? "Next Cosigner" : "Continue")
              .font(.hbHeadline)
              .foregroundStyle(.white)
              .padding(.horizontal, 24)
              .padding(.vertical, 14)
              .background(viewModel.currentCosignerComplete ? Color.hbBitcoinOrange : Color.hbBorder)
              .clipShape(RoundedRectangle(cornerRadius: 12))
          }
          .disabled(!viewModel.currentCosignerComplete)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
      }
      .padding(.top, 16)
    }
    .sheet(isPresented: $showScanner) {
      URScannerSheet(expectedTypes: [.hdKey], onCancel: { showScanner = false }) { result in
        handleScanResult(result)
        showScanner = false
      }
    }
  }

  private func pasteFromClipboard() {
    if let text = UIPasteboard.general.string {
      let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
      let isTestnet = viewModel.network != .mainnet
      if let normalized = URService.normalizeXpub(raw, isTestnet: isTestnet) {
        viewModel.cosignerXpubs[viewModel.currentCosignerIndex] = normalized
      } else {
        viewModel.cosignerXpubs[viewModel.currentCosignerIndex] = raw
      }
    }
  }

  private func toggleXpubFormat() {
    let idx = viewModel.currentCosignerIndex
    let current = viewModel.cosignerXpubs[idx].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !current.isEmpty else { return }

    let isTestnet = viewModel.network != .mainnet
    if let toggled = URService.toggleXpubFormat(current, isTestnet: isTestnet) {
      viewModel.cosignerXpubs[idx] = toggled
    }
  }

  private func goBack() {
    if viewModel.currentCosignerIndex > 0 {
      viewModel.currentCosignerIndex -= 1
    } else {
      viewModel.goBack()
    }
  }

  private func goNext() {
    // Validate current cosigner
    let idx = viewModel.currentCosignerIndex
    if let error = viewModel.validateCosignerXpub(viewModel.cosignerXpubs[idx], at: idx) {
      validationError = error
      return
    }
    if let error = viewModel.validateFingerprint(viewModel.cosignerFingerprints[idx]) {
      validationError = error
      return
    }
    if let error = viewModel.validateDerivationPath(viewModel.cosignerDerivationPaths[idx]) {
      validationError = error
      return
    }

    validationError = nil

    if viewModel.currentCosignerIndex < viewModel.totalCosigners - 1 {
      viewModel.currentCosignerIndex += 1
    } else {
      viewModel.goToNext()
    }
  }

  private func handleScanResult(_ result: AppURResult) {
    switch result {
    case .hdKey(var xpub, let fingerprint, let derivationPath):
      let idx = viewModel.currentCosignerIndex

      // Validate derivation path network before accepting the scan
      if !derivationPath.isEmpty {
        if let error = viewModel.validateDerivationPath(derivationPath) {
          validationError = error
          return
        }
      }

      // Auto-convert any xpub/tpub/Zpub/Vpub to the standard format for the network
      let isTestnet = viewModel.network != .mainnet
      if let normalized = URService.normalizeXpub(xpub, isTestnet: isTestnet) {
        xpub = normalized
      }

      viewModel.cosignerXpubs[idx] = xpub
      if !fingerprint.isEmpty {
        viewModel.cosignerFingerprints[idx] = fingerprint
      }
      if !derivationPath.isEmpty {
        viewModel.cosignerDerivationPaths[idx] = derivationPath
      }
    default:
      validationError = "Unexpected QR code type. Expected crypto-hdkey or crypto-account."
    }
  }
}

private struct CosignerSlot: View {
  let index: Int
  let isCurrent: Bool
  let isComplete: Bool

  var body: some View {
    VStack(spacing: 4) {
      ZStack {
        RoundedRectangle(cornerRadius: 8)
          .fill(isComplete ? Color.hbBitcoinOrange.opacity(0.2) : Color.hbSurface)
          .frame(height: 44)
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .strokeBorder(
                isCurrent ? Color.hbBitcoinOrange :
                  isComplete ? Color.hbBitcoinOrange.opacity(0.5) : Color.hbBorder,
                lineWidth: isCurrent ? 2 : 0.5
              )
          )

        if isComplete {
          Image(systemName: "lock.fill")
            .font(.system(size: 16))
            .foregroundStyle(Color.hbBitcoinOrange)
        } else {
          Image(systemName: "lock.open")
            .font(.system(size: 16))
            .foregroundStyle(Color.hbTextSecondary)
        }
      }

      Text("\(index + 1)")
        .font(.hbLabel(11))
        .foregroundStyle(isCurrent ? Color.hbBitcoinOrange : Color.hbTextSecondary)
    }
  }
}
