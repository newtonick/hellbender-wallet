import LocalAuthentication
import SwiftData
import SwiftUI

struct ContentView: View {
  @Query private var wallets: [WalletProfile]
  @AppStorage(Constants.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
  @AppStorage(Constants.appLockEnabledKey) private var appLockEnabled = false
  @Environment(\.scenePhase) private var scenePhase
  @State private var isLocked = true
  @State private var isAuthenticating = false
  @State private var backgroundTime: Date?

  private var hasActiveWallet: Bool {
    wallets.contains { $0.isActive }
  }

  private var shouldShowLock: Bool {
    appLockEnabled && isLocked
  }

  var body: some View {
    ZStack {
      Group {
        if hasCompletedOnboarding, hasActiveWallet {
          MainTabView()
        } else {
          SetupWizardView()
        }
      }
      .background(Color.hbBackground)

      if shouldShowLock {
        AppLockView(isAuthenticating: $isAuthenticating, onAuthenticate: authenticate)
      }
    }
    .onAppear {
      if appLockEnabled {
        authenticate()
      } else {
        isLocked = false
      }
    }
    .onChange(of: scenePhase) { _, newPhase in
      if appLockEnabled {
        if newPhase == .background {
          if backgroundTime == nil {
            backgroundTime = Date()
          }
        } else if newPhase == .active {
          if let bgTime = backgroundTime, Date().timeIntervalSince(bgTime) >= 60 {
            isLocked = true
            authenticate()
          }
          backgroundTime = nil
        }
      }
    }
  }

  private func authenticate() {
    guard !isAuthenticating else { return }
    isAuthenticating = true

    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      // If authentication is unavailable, let the user in
      isLocked = false
      isAuthenticating = false
      return
    }

    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock \(Constants.appName)") { success, _ in
      DispatchQueue.main.async {
        if success {
          isLocked = false
        }
        isAuthenticating = false
      }
    }
  }
}

// MARK: - Lock Screen

private struct AppLockView: View {
  @Binding var isAuthenticating: Bool
  let onAuthenticate: () -> Void

  private var biometricIcon: String {
    let context = LAContext()
    _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    switch context.biometryType {
    case .faceID: return "faceid"
    case .touchID: return "touchid"
    case .opticID: return "opticid"
    default: return "lock.fill"
    }
  }

  var body: some View {
    ZStack {
      Color.hbBackground
        .ignoresSafeArea()

      VStack(spacing: 24) {
        Spacer()

        Image(systemName: biometricIcon)
          .font(.system(size: 56))
          .foregroundStyle(Color.hbBitcoinOrange)

        Text(Constants.appName)
          .font(.hbDisplay(28))
          .foregroundStyle(Color.hbTextPrimary)

        Text("Locked")
          .font(.hbBody())
          .foregroundStyle(Color.hbTextSecondary)

        Spacer()

        Button(action: onAuthenticate) {
          Text("Unlock")
            .hbPrimaryButton()
        }
        .disabled(isAuthenticating)
        .padding(.horizontal, 24)
        .padding(.bottom, 48)
      }
    }
  }
}
