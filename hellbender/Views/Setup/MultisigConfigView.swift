import SwiftUI

struct MultisigConfigView: View {
  @Bindable var viewModel: SetupWizardViewModel
  @State private var showingMSheet = false
  @State private var showingNSheet = false

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        Text("Multisig Configuration")
          .font(.hbDisplay(28))
          .foregroundStyle(Color.hbTextPrimary)
          .padding(.top, 16)

        VStack(spacing: 16) {
          Text("How many signatures are required?")
            .font(.hbBody(15))
            .foregroundStyle(Color.hbTextSecondary)

          // Interactive M-of-N display
          HStack(spacing: 12) {
            // M Selector Button
            Button(action: { showingMSheet = true }) {
              HStack(spacing: 4) {
                Image(systemName: "chevron.up.chevron.down")
                  .font(.system(size: 14, weight: .bold))
                  .foregroundStyle(Color.hbBitcoinOrange.opacity(0.7))
                Text("\(viewModel.requiredSignatures)")
                  .font(.hbDisplay(48))
                  .foregroundStyle(Color.hbBitcoinOrange)
              }
            }
            .sheet(isPresented: $showingMSheet) {
              NumberPickerSheet(
                title: "Required Signatures",
                range: 1 ... viewModel.totalCosigners,
                selection: $viewModel.requiredSignatures
              )
            }

            Text("of")
              .font(.hbBody(20))
              .foregroundStyle(Color.hbTextSecondary)

            // N Selector Button
            Button(action: { showingNSheet = true }) {
              HStack(spacing: 4) {
                Text("\(viewModel.totalCosigners)")
                  .font(.hbDisplay(48))
                  .foregroundStyle(Color.hbTextPrimary)
                Image(systemName: "chevron.up.chevron.down")
                  .font(.system(size: 14, weight: .bold))
                  .foregroundStyle(Color.hbTextSecondary)
              }
            }
            .sheet(isPresented: $showingNSheet) {
              NumberPickerSheet(
                title: "Total Cosigners",
                range: Constants.minCosigners ... Constants.maxCosigners,
                selection: $viewModel.totalCosigners,
                onChange: { newN in
                  if viewModel.requiredSignatures > newN {
                    viewModel.requiredSignatures = newN
                  }
                }
              )
            }
          }
        }
        .padding(.bottom, 0)

        VStack(spacing: 24) {
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

          // Electrum server
          ElectrumServerSetupSection(viewModel: viewModel, initiallyExpanded: viewModel.network == .mainnet)

          // Advanced
          WalletAdvancedSetupSection(viewModel: viewModel)
        }
        .padding(.horizontal, 24)

        HStack(spacing: 16) {
          Button(action: { viewModel.goBack() }) {
            Text("Back")
              .font(.hbBody(16))
              .foregroundStyle(Color.hbTextSecondary)
          }

          Spacer()

          Button(action: { viewModel.goToNext() }) {
            Text("Next")
              .font(.hbHeadline)
              .foregroundStyle(.white)
              .padding(.horizontal, 32)
              .padding(.vertical, 14)
              .background(Color.hbBitcoinOrange)
              .clipShape(RoundedRectangle(cornerRadius: 12))
          }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
      }
    }
    .scrollDismissesKeyboard(.interactively)
  }
}
