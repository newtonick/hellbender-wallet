import SwiftUI

struct DescriptorImportView: View {
  @Bindable var viewModel: SetupWizardViewModel
  @State private var showScanner = false

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        Text("Import Descriptor")
          .font(.hbDisplay(28))
          .foregroundStyle(Color.hbTextPrimary)
          .padding(.top, 16)

        Text("Paste or scan a multisig output descriptor")
          .font(.hbBody(15))
          .foregroundStyle(Color.hbTextSecondary)
          .multilineTextAlignment(.center)

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Output Descriptor")
              .font(.hbLabel())
              .foregroundStyle(Color.hbTextSecondary)

            Spacer()

            Button(action: {
              if let text = UIPasteboard.general.string {
                viewModel.importedDescriptorText = text.trimmingCharacters(in: .whitespacesAndNewlines)
              }
            }) {
              Label("Paste", systemImage: "doc.on.clipboard")
                .font(.hbLabel())
                .foregroundStyle(Color.hbSteelBlue)
            }
          }

          TextEditor(text: $viewModel.importedDescriptorText)
            .font(.hbMono(11))
            .frame(minHeight: 120)
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(Color.hbSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.hbTextPrimary)

          Text("Expected format: wsh(sortedmulti(M,[fp/path]xpub/0/*,...))")
            .font(.hbMono(10))
            .foregroundStyle(Color.hbTextSecondary)
        }
        .hbCard()
        .padding(.horizontal, 24)

        Button(action: { showScanner = true }) {
          Label("Scan Descriptor QR", systemImage: "qrcode.viewfinder")
            .hbSecondaryButton()
        }
        .padding(.horizontal, 24)

        // Network picker
        VStack(spacing: 8) {
          Text("Bitcoin Network")
            .font(.hbLabel())
            .foregroundStyle(Color.hbTextSecondary)

          Picker("Bitcoin Network", selection: $viewModel.network) {
            ForEach(BitcoinNetwork.allCases) { network in
              Text(network.displayName).tag(network)
            }
          }
          .pickerStyle(.segmented)
        }
        .hbCard()
        .padding(.horizontal, 24)

        if let mismatchError = viewModel.descriptorNetworkMismatchError {
          Text(mismatchError)
            .font(.hbLabel(13))
            .foregroundStyle(Color.hbError)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }

        // Electrum server
        ElectrumServerSetupSection(viewModel: viewModel)
          .padding(.horizontal, 24)

        // Block explorer & gap limit
        WalletAdvancedSetupSection(viewModel: viewModel)
          .padding(.horizontal, 24)

        HStack(spacing: 16) {
          Button(action: { viewModel.goBack() }) {
            Text("Back")
              .font(.hbBody(16))
              .foregroundStyle(Color.hbTextSecondary)
          }

          Spacer()

          Button(action: { viewModel.goToNext() }) {
            let canImport = !viewModel.importedDescriptorText.isEmpty && viewModel.descriptorNetworkMismatchError == nil
            Text("Import")
              .font(.hbHeadline)
              .foregroundStyle(.white)
              .padding(.horizontal, 32)
              .padding(.vertical, 14)
              .background(canImport ? Color.hbBitcoinOrange : Color.hbBorder)
              .clipShape(RoundedRectangle(cornerRadius: 12))
          }
          .disabled(viewModel.importedDescriptorText.isEmpty || viewModel.descriptorNetworkMismatchError != nil)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .sheet(isPresented: $showScanner) {
      URScannerSheet { result in
        if case let .descriptor(text) = result {
          viewModel.importedDescriptorText = text
        }
        showScanner = false
      }
    }
  }
}
