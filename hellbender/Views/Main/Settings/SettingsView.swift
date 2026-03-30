import LocalAuthentication
import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "hellbender", category: "Settings")

struct SettingsView: View {
  @Environment(\.modelContext) private var modelContext
  @State private var showLogExport = false

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
          // Security
          AppLockSettingsSection()

          // Appearance
          Section("Appearance") {
            AppearanceSettingsRow()
          }

          // Fee Estimation
          Section("Fee Estimation") {
            FeeSettingsRow()
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

              Button(action: { showLogExport = true }) {
                Image(systemName: "doc.text.magnifyingglass")
                  .font(.system(size: 14))
                  .foregroundStyle(Color.hbTextSecondary)
              }
              .buttonStyle(.plain)
            }
            .listRowBackground(Color.hbSurface)
          }
        }
        .scrollContentBackground(.hidden)
      }
      .background(Color.hbBackground)
      .navigationTitle("")
      .sheet(isPresented: $showLogExport) {
        LogExportSheet()
      }
    }
  }
}

// MARK: - Appearance Settings

private struct AppearanceSettingsRow: View {
  @AppStorage(Constants.themeKey) private var themeRaw = AppTheme.system.rawValue

  var body: some View {
    Picker("Theme", selection: $themeRaw) {
      ForEach(AppTheme.allCases, id: \.rawValue) { theme in
        Text(theme.displayName).tag(theme.rawValue)
      }
    }
    .tint(Color.hbBitcoinOrange)
    .foregroundStyle(Color.hbTextPrimary)
    .onChange(of: themeRaw) { _, new in
      if let t = AppTheme(rawValue: new) {
        logger.info("Theme changed to \(t.displayName, privacy: .public)")
        ThemeManager.shared.apply(t)
      }
    }
    .listRowBackground(Color.hbSurface)
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

// MARK: - Fee Settings

private struct FeeSettingsRow: View {
  @AppStorage(Constants.feeSourceKey) private var feeSourceRaw = FeeSource.electrum.rawValue

  var body: some View {
    Picker("Fee Source", selection: $feeSourceRaw) {
      ForEach(FeeSource.allCases, id: \.rawValue) { source in
        Text(source.displayName).tag(source.rawValue)
      }
    }
    .tint(Color.hbBitcoinOrange)
    .foregroundStyle(Color.hbTextPrimary)
    .listRowBackground(Color.hbSurface)
    .onChange(of: feeSourceRaw) { _, new in
      logger.info("Fee source changed to \(new, privacy: .public)")
    }
  }
}

// MARK: - Fiat Settings

private struct FiatSettingsRow: View {
  @AppStorage(Constants.fiatEnabledKey) private var fiatEnabled = false
  @AppStorage(Constants.fiatCurrencyKey) private var fiatCurrency = "USD"
  @AppStorage(Constants.fiatSourceKey) private var fiatSourceRaw = FiatSource.zeus.rawValue
  @State private var fiatService = FiatPriceService.shared

  var body: some View {
    VStack(spacing: 0) {
      Toggle(isOn: Binding(
        get: { fiatEnabled },
        set: { new in
          logger.info("Fiat display \(new ? "enabled" : "disabled", privacy: .public)")
          fiatEnabled = new
        }
      )) {
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
        Picker("Price Source", selection: $fiatSourceRaw) {
          ForEach(FiatSource.allCases, id: \.rawValue) { source in
            Text(source.displayName).tag(source.rawValue)
          }
        }
        .tint(Color.hbBitcoinOrange)
        .foregroundStyle(Color.hbTextPrimary)
        .padding(.top, 12)
        .onChange(of: fiatSourceRaw) {
          logger.info("Fiat source changed to \(fiatSourceRaw, privacy: .public)")
          fiatService.resetCache()
          Task { await fiatService.fetchRates() }
        }

        Picker("Currency", selection: $fiatCurrency) {
          ForEach(FiatPriceService.availableCurrencies, id: \.code) { currency in
            Text(currency.code).tag(currency.code)
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

private struct AppLockSettingsSection: View {
  @AppStorage(Constants.appLockEnabledKey) private var appLockEnabled = false
  @AppStorage(Constants.appLockTimeoutKey) private var lockTimeout = 60
  @State private var showBiometricError = false
  @State private var biometricErrorMessage = ""
  @State private var showSetPIN = false
  @State private var showRemovePIN = false
  @State private var lockVM = AppLockViewModel()

  private static let timeoutOptions: [(String, Int)] = [
    ("1 minute", 60),
    ("5 minutes", 300),
    ("15 minutes", 900),
    ("30 minutes", 1800),
    ("60 minutes", 3600),
  ]

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
    Section("Security") {
      Toggle(isOn: Binding(
        get: { appLockEnabled },
        set: { newValue in
          if newValue {
            authenticateToEnable()
          } else {
            logger.info("App lock disabled")
            lockVM.removePIN()
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
      .listRowBackground(Color.hbSurface)
      .alert("Authentication Unavailable", isPresented: $showBiometricError) {
        Button("OK") {}
      } message: {
        Text(biometricErrorMessage)
      }
      .sheet(isPresented: $showSetPIN) {
        SetPINSheet(lockVM: lockVM)
      }
      .sheet(isPresented: $showRemovePIN) {
        RemovePINSheet(lockVM: lockVM)
      }

      if appLockEnabled {
        Picker("Lock After", selection: $lockTimeout) {
          ForEach(Self.timeoutOptions, id: \.1) { option in
            Text(option.0).tag(option.1)
          }
        }
        .tint(Color.hbBitcoinOrange)
        .foregroundStyle(Color.hbTextPrimary)
        .listRowBackground(Color.hbSurface)
        .onChange(of: lockTimeout) { _, new in
          logger.info("Lock timeout changed to \(new)s")
        }

        if lockVM.hasPIN {
          Button(role: .destructive) {
            showRemovePIN = true
          } label: {
            Text("Remove PIN")
              .foregroundStyle(Color.hbError)
          }
          .listRowBackground(Color.hbSurface)
        } else {
          Button {
            showSetPIN = true
          } label: {
            HStack {
              Text("Add Additional PIN")
                .foregroundStyle(Color.hbBitcoinOrange)
              Spacer()
              Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.hbTextSecondary)
            }
          }
          .listRowBackground(Color.hbSurface)
        }
      }
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
          logger.info("App lock enabled")
          appLockEnabled = true
        }
      }
    }
  }
}

// MARK: - Set PIN Sheet

private struct SetPINSheet: View {
  @Bindable var lockVM: AppLockViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var step: SetPINStep = .create
  @State private var firstPIN = ""
  @State private var confirmPIN = ""
  @State private var error = ""

  private enum SetPINStep {
    case create
    case confirm
  }

  var body: some View {
    NavigationStack {
      VStack {
        Spacer()

        switch step {
        case .create:
          PINPadView(
            title: "Create PIN",
            subtitle: error,
            dotCount: 8,
            minDigits: 4,
            mode: .create,
            pin: $firstPIN,
            isDisabled: false,
            onComplete: { pin in
              firstPIN = pin
              error = ""
              confirmPIN = ""
              step = .confirm
            },
            hint: "Choose a PIN between 4 and 8 digits"
          )
        case .confirm:
          PINPadView(
            title: "Confirm PIN",
            subtitle: error,
            dotCount: firstPIN.count,
            minDigits: firstPIN.count,
            mode: .verify,
            pin: $confirmPIN,
            isDisabled: false,
            onComplete: { pin in
              if pin == firstPIN {
                lockVM.setPIN(pin)
                dismiss()
              } else {
                error = "PINs don't match — try again"
                firstPIN = ""
                confirmPIN = ""
                step = .create
              }
            }
          )
        }

        Spacer()
      }
      .padding(.horizontal, 16)
      .background(Color.hbBackground)
      .navigationTitle("Set PIN")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .foregroundStyle(Color.hbBitcoinOrange)
        }
      }
    }
  }
}

// MARK: - Remove PIN Sheet

private struct RemovePINSheet: View {
  @Bindable var lockVM: AppLockViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var pin = ""
  @State private var error = ""
  @State private var lockoutTimer: Timer?

  var body: some View {
    NavigationStack {
      VStack {
        Spacer()

        PINPadView(
          title: "Enter Current PIN",
          subtitle: lockVM.isLockedOut ? lockVM.lockoutRemainingText : error,
          dotCount: lockVM.storedPINLength,
          minDigits: lockVM.storedPINLength,
          mode: .verify,
          pin: $pin,
          isDisabled: lockVM.isLockedOut,
          onComplete: { entered in
            if lockVM.verifyPIN(entered) {
              // verifyPIN unlocked — re-lock since we're in settings
              lockVM.isLocked = false
              lockVM.removePIN()
              dismiss()
            } else {
              error = lockVM.pinError
              pin = ""
              startLockoutTimerIfNeeded()
            }
          }
        )

        Spacer()
      }
      .padding(.horizontal, 16)
      .background(Color.hbBackground)
      .navigationTitle("Remove PIN")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .foregroundStyle(Color.hbBitcoinOrange)
        }
      }
      .onAppear { startLockoutTimerIfNeeded() }
      .onDisappear { lockoutTimer?.invalidate() }
    }
  }

  private func startLockoutTimerIfNeeded() {
    guard lockVM.isLockedOut else { return }
    lockoutTimer?.invalidate()
    lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak lockVM] timer in
      MainActor.assumeIsolated {
        guard let lockVM else {
          timer.invalidate()
          return
        }
        if !lockVM.isLockedOut {
          timer.invalidate()
          error = ""
        } else {
          error = lockVM.lockoutRemainingText
        }
      }
    }
  }
}

// MARK: - Log Export Sheet

private struct LogExportSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var logText: String = ""
  @State private var isLoading = true
  @State private var copied = false
  @State private var hours: Double = 1

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Time range picker
        HStack(spacing: 12) {
          Text("Last")
            .font(.hbLabel())
            .foregroundStyle(Color.hbTextSecondary)
          Picker("", selection: $hours) {
            Text("1h").tag(1.0)
            Text("4h").tag(4.0)
            Text("12h").tag(12.0)
            Text("24h").tag(24.0)
          }
          .pickerStyle(.segmented)
          .onChange(of: hours) {
            loadLogs()
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

        if isLoading {
          Spacer()
          ProgressView()
            .tint(Color.hbBitcoinOrange)
          Spacer()
        } else {
          ScrollView {
            Text(logText)
              .font(.hbMono(11))
              .foregroundStyle(Color.hbTextPrimary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(12)
              .textSelection(.enabled)
          }
          .background(Color.hbSurfaceElevated)
        }
      }
      .background(Color.hbBackground)
      .navigationTitle("Debug Logs")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
            .foregroundStyle(Color.hbBitcoinOrange)
        }
        ToolbarItem(placement: .primaryAction) {
          HStack(spacing: 12) {
            ShareLink(item: logText) {
              Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14))
            }
            .foregroundStyle(Color.hbBitcoinOrange)

            Button(action: copyLogs) {
              Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14))
                .foregroundStyle(copied ? Color.hbSuccess : Color.hbBitcoinOrange)
            }
          }
        }
      }
      .onAppear { loadLogs() }
    }
  }

  private func loadLogs() {
    isLoading = true
    Task {
      let text: String
      do {
        text = try LogExporter.collectLogs(hours: hours)
      } catch {
        text = "Failed to read logs: \(error.localizedDescription)"
      }
      await MainActor.run {
        logText = text
        isLoading = false
      }
    }
  }

  private func copyLogs() {
    UIPasteboard.general.string = logText
    copied = true
    Task {
      try? await Task.sleep(for: .seconds(2))
      await MainActor.run { copied = false }
    }
  }
}
