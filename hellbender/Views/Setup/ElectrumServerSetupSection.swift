import SwiftUI

struct ElectrumServerSetupSection: View {
  @Bindable var viewModel: SetupWizardViewModel

  var body: some View {
    VStack(spacing: 12) {
      Text("Electrum Server")
        .font(.hbLabel())
        .foregroundStyle(Color.hbTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: .leading, spacing: 6) {
        Text("Host")
          .font(.hbLabel(11))
          .foregroundStyle(Color.hbTextSecondary)
        TextField(viewModel.network.defaultElectrumHost ?? "Enter server host", text: $viewModel.electrumHost)
          .font(.hbMono(14))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .padding(10)
          .background(Color.hbSurfaceElevated)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .foregroundStyle(Color.hbTextPrimary)
      }

      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Port")
            .font(.hbLabel(11))
            .foregroundStyle(Color.hbTextSecondary)
          TextField(String(viewModel.network.defaultElectrumPort), text: $viewModel.electrumPort)
            .font(.hbMono(14))
            .keyboardType(.numberPad)
            .padding(10)
            .background(Color.hbSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.hbTextPrimary)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Protocol")
            .font(.hbLabel(11))
            .foregroundStyle(Color.hbTextSecondary)
          Picker("Protocol", selection: Binding(
            get: {
              switch viewModel.electrumSSL {
              case 1: 1
              case 2: 2
              default: viewModel.network.usesSSL ? 2 : 1
              }
            },
            set: { viewModel.electrumSSL = $0 }
          )) {
            Text("TCP").tag(1)
            Text("SSL").tag(2)
          }
          .pickerStyle(.segmented)
        }
      }

      if viewModel.network.defaultElectrumHost != nil {
        Text("Leave blank to use defaults for \(viewModel.network.displayName)")
          .font(.hbBody(11))
          .foregroundStyle(Color.hbTextSecondary)
      } else {
        Text("Electrum Server config is required for \(viewModel.network.displayName)")
          .font(.hbBody(11))
          .foregroundStyle(Color.hbBitcoinOrange)
      }
    }
    .hbCard()
  }
}

struct WalletAdvancedSetupSection: View {
  @Bindable var viewModel: SetupWizardViewModel

  var body: some View {
    VStack(spacing: 12) {
      Text("Advanced")
        .font(.hbLabel())
        .foregroundStyle(Color.hbTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Address Gap Limit")
            .font(.hbLabel(11))
            .foregroundStyle(Color.hbTextSecondary)
          TextField("50", text: $viewModel.addressGapLimit)
            .font(.hbMono(14))
            .keyboardType(.numberPad)
            .padding(10)
            .background(Color.hbSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.hbTextPrimary)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Block Explorer")
            .font(.hbLabel(11))
            .foregroundStyle(Color.hbTextSecondary)
          TextField("mempool.space", text: $viewModel.blockExplorerHost)
            .font(.hbMono(14))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(10)
            .background(Color.hbSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.hbTextPrimary)
        }
      }
    }
    .hbCard()
  }
}
