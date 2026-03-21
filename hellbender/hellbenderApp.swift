import SwiftData
import SwiftUI

@main
struct hellbenderApp: App {
  let modelContainer: ModelContainer

  init() {
    do {
      let schema = Schema([WalletProfile.self, CosignerInfo.self, WalletLabel.self, FrozenUTXO.self, SavedPSBT.self])
      let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
      modelContainer = try ModelContainer(for: schema, configurations: [config])
      BitcoinService.shared.modelContainer = modelContainer
    } catch {
      fatalError("Failed to create ModelContainer: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
    }
    .modelContainer(modelContainer)
  }
}

// MARK: - Root View

struct RootView: View {
  let themeManager = ThemeManager.shared
  @AppStorage(Constants.themeKey) private var themeRaw = AppTheme.system.rawValue
  @Environment(\.colorScheme) private var systemColorScheme

  private var isSystemTheme: Bool {
    AppTheme(rawValue: themeRaw) == .system
  }

  var body: some View {
    ContentView()
      // When System theme is active, pass nil so SwiftUI follows the OS —
      // this lets @Environment(\.colorScheme) reflect real OS changes.
      .preferredColorScheme(isSystemTheme ? nil : themeManager.theme.colorScheme)
      .task(id: systemColorScheme) {
        // Using task(id:) instead of onChange so that transient colorScheme
        // flips during sheet dismissal animations are cancelled before they
        // apply, preventing the theme from briefly snapping to the wrong palette.
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        if isSystemTheme {
          themeManager.applySystemColorScheme(systemColorScheme)
        }
      }
      .onChange(of: themeRaw) { _, new in
        if AppTheme(rawValue: new) == .system {
          themeManager.applySystemColorScheme(systemColorScheme)
        }
      }
  }
}
