import LocalAuthentication
import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var wallets: [WalletProfile]
  @State private var viewModel = WalletManagerViewModel()
  @State private var walletToDelete: WalletProfile?
  @State private var showAddWallet = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Text("Settings")
          .font(.hbAmountLarge)
          .foregroundStyle(Color.hbTextPrimary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.top, 8)
          .padding(.bottom, 4)

        List {
          // Wallets
          Section("Wallets") {
            ForEach(wallets) { wallet in
              HStack(spacing: 12) {
                Button {
                  if !wallet.isActive {
                    viewModel.setActiveWallet(wallet, allWallets: wallets, modelContext: modelContext)
                  }
                } label: {
                  Image(systemName: wallet.isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(wallet.isActive ? Color.hbBitcoinOrange : Color.hbTextSecondary)
                }
                .buttonStyle(.plain)

                NavigationLink(destination: WalletInfoView(wallet: wallet)) {
                  HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                      Text(wallet.name)
                        .font(.hbHeadline)
                        .foregroundStyle(Color.hbTextPrimary)

                      HStack(spacing: 8) {
                        Text(wallet.multisigDescription)
                          .font(.hbMono(12))
                          .foregroundStyle(Color.hbTextSecondary)

                        NetworkBadge(network: wallet.bitcoinNetwork)
                      }
                    }

                    Spacer()
                  }
                }
              }
              .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                  walletToDelete = wallet
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
              .listRowBackground(Color.hbSurface)
            }

            if wallets.isEmpty {
              Text("No wallets configured")
                .foregroundStyle(Color.hbTextSecondary)
                .listRowBackground(Color.hbSurface)
            }

            Button(action: { showAddWallet = true }) {
              Label("Add Wallet", systemImage: "plus.circle")
                .font(.hbBody(15))
                .foregroundStyle(Color.hbBitcoinOrange)
            }
            .listRowBackground(Color.hbSurface)
          }

          // Security
          Section("Security") {
            AppLockSettingsRow()
          }

          // Fiat Display
          Section("Fiat Display") {
            FiatSettingsRow()
          }

          // About
          Section("About") {
            HStack {
              Text("Version")
                .foregroundStyle(Color.hbTextPrimary)
              Spacer()
              Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                .foregroundStyle(Color.hbTextSecondary)
            }
            .listRowBackground(Color.hbSurface)
          }
        }
        .scrollContentBackground(.hidden)
      }
      .background(Color.hbBackground)
      .navigationTitle("")
      .sheet(isPresented: $showAddWallet) {
        SetupWizardView(canDismiss: true)
          .interactiveDismissDisabled()
      }
      .alert("Delete Wallet?", isPresented: .init(
        get: { walletToDelete != nil },
        set: { if !$0 { walletToDelete = nil } }
      )) {
        Button("Delete", role: .destructive) {
          if let wallet = walletToDelete {
            viewModel.deleteWallet(wallet, modelContext: modelContext)
          }
          walletToDelete = nil
        }
        Button("Cancel", role: .cancel) { walletToDelete = nil }
      } message: {
        Text("This will permanently delete \"\(walletToDelete?.name ?? "")\" and all its data.")
      }
    }
  }
}

// MARK: - Denomination Settings

private struct DenominationSettingsRow: View {
  @AppStorage(Constants.denominationKey) private var denomination: String = Denomination.sats.rawValue

  var body: some View {
    HStack {
      Text("Denomination")
        .foregroundStyle(Color.hbTextPrimary)
      Spacer()
      Picker("", selection: $denomination) {
        ForEach(Denomination.allCases, id: \.rawValue) { denom in
          Text(denom.rawValue).tag(denom.rawValue)
        }
      }
      .tint(Color.hbBitcoinOrange)
    }
    .listRowBackground(Color.hbSurface)
  }
}

// MARK: - Fiat Settings

private struct FiatSettingsRow: View {
  @AppStorage(Constants.fiatEnabledKey) private var fiatEnabled = false
  @AppStorage(Constants.fiatCurrencyKey) private var fiatCurrency = "USD"

  var body: some View {
    VStack(spacing: 0) {
      Toggle(isOn: $fiatEnabled) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Show Fiat Price")
            .foregroundStyle(Color.hbTextPrimary)
          Text("Display estimated fiat value alongside sats")
            .font(.hbBody(12))
            .foregroundStyle(Color.hbTextSecondary)
        }
      }
      .tint(Color.hbBitcoinOrange)

      if fiatEnabled {
        Picker("Currency", selection: $fiatCurrency) {
          ForEach(FiatPriceService.availableCurrencies, id: \.code) { currency in
            Text("\(currency.code) – \(currency.name)").tag(currency.code)
          }
        }
        .tint(Color.hbBitcoinOrange)
        .foregroundStyle(Color.hbTextPrimary)
        .padding(.top, 12)
      }
    }
    .listRowBackground(Color.hbSurface)
  }
}

// MARK: - App Lock Settings

private struct AppLockSettingsRow: View {
  @AppStorage(Constants.appLockEnabledKey) private var appLockEnabled = false
  @State private var showBiometricError = false
  @State private var biometricErrorMessage = ""

  private var biometricLabel: String {
    let context = LAContext()
    _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    switch context.biometryType {
    case .faceID: return "Face ID"
    case .touchID: return "Touch ID"
    case .opticID: return "Optic ID"
    default: return "Passcode"
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      Toggle(isOn: Binding(
        get: { appLockEnabled },
        set: { newValue in
          if newValue {
            authenticateToEnable()
          } else {
            appLockEnabled = false
          }
        }
      )) {
        VStack(alignment: .leading, spacing: 2) {
          Text("App Lock")
            .foregroundStyle(Color.hbTextPrimary)
          Text("Require \(biometricLabel) to open app")
            .font(.hbBody(12))
            .foregroundStyle(Color.hbTextSecondary)
        }
      }
      .tint(Color.hbBitcoinOrange)
    }
    .listRowBackground(Color.hbSurface)
    .alert("Authentication Unavailable", isPresented: $showBiometricError) {
      Button("OK") {}
    } message: {
      Text(biometricErrorMessage)
    }
  }

  private func authenticateToEnable() {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      biometricErrorMessage = error?.localizedDescription ?? "Authentication is not available on this device."
      showBiometricError = true
      return
    }
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Verify your identity to enable app lock") { success, _ in
      DispatchQueue.main.async {
        if success {
          appLockEnabled = true
        }
      }
    }
  }
}
