import SwiftUI

// MARK: - Theme Data

struct HBTheme {
  var background: Color
  var surface: Color
  var surfaceElevated: Color
  var border: Color
  var textPrimary: Color
  var textSecondary: Color
  var accent: Color
  var success: Color
  var error: Color
  var colorScheme: ColorScheme? = .dark

  static let system = HBTheme(
    background: Color(.systemBackground),
    surface: Color(.secondarySystemBackground),
    surfaceElevated: Color(.tertiarySystemBackground),
    border: Color(.separator),
    textPrimary: Color(.label),
    textSecondary: Color(.secondaryLabel),
    accent: Color(red: 0.969, green: 0.576, blue: 0.102),
    success: Color(.systemGreen),
    error: Color(.systemRed),
    colorScheme: nil
  )

  static let dark = HBTheme(
    background: Color(red: 0.039, green: 0.039, blue: 0.059),
    surface: Color(red: 0.082, green: 0.082, blue: 0.098),
    surfaceElevated: Color(red: 0.110, green: 0.110, blue: 0.141),
    border: Color(red: 0.165, green: 0.165, blue: 0.208),
    textPrimary: Color(red: 0.910, green: 0.902, blue: 0.890),
    textSecondary: Color(red: 0.420, green: 0.420, blue: 0.463),
    accent: Color(red: 0.969, green: 0.576, blue: 0.102),
    success: Color(red: 0.176, green: 0.545, blue: 0.341),
    error: Color(red: 0.851, green: 0.267, blue: 0.267),
    colorScheme: .dark
  )

  static let light = HBTheme(
    background: Color(red: 1.000, green: 1.000, blue: 1.000),
    surface: Color(red: 0.949, green: 0.949, blue: 0.969),
    surfaceElevated: Color(red: 1.000, green: 1.000, blue: 1.000),
    border: Color(red: 0.776, green: 0.776, blue: 0.784),
    textPrimary: Color(red: 0.110, green: 0.110, blue: 0.118),
    textSecondary: Color(red: 0.557, green: 0.557, blue: 0.576),
    accent: Color(red: 0.969, green: 0.576, blue: 0.102),
    success: Color(red: 0.204, green: 0.780, blue: 0.349),
    error: Color(red: 1.000, green: 0.231, blue: 0.188),
    colorScheme: .light
  )
}

// MARK: - App Theme Enum

enum AppTheme: String, CaseIterable {
  case system
  case dark
  case light

  var displayName: String {
    switch self {
    case .system: "System"
    case .dark: "Dark"
    case .light: "Light"
    }
  }

  var theme: HBTheme {
    switch self {
    case .system: .system
    case .dark: .dark
    case .light: .light
    }
  }
}

// MARK: - Theme Manager

@Observable
final class ThemeManager {
  static let shared = ThemeManager()
  private(set) var theme: HBTheme = .dark

  private init() {
    let saved = UserDefaults.standard.string(forKey: Constants.themeKey) ?? AppTheme.system.rawValue
    theme = (AppTheme(rawValue: saved) ?? .system).theme
  }

  func apply(_ appTheme: AppTheme) {
    theme = appTheme.theme
    UserDefaults.standard.set(appTheme.rawValue, forKey: Constants.themeKey)
  }

  /// Sets the displayed theme to the appropriate custom palette for the given OS color scheme.
  /// Only used when the System theme is selected — does not save to UserDefaults.
  func applySystemColorScheme(_ colorScheme: ColorScheme) {
    theme = colorScheme == .dark ? .dark : .light
  }
}

// MARK: - Color Palette

extension Color {
  /// Backgrounds
  static var hbBackground: Color {
    ThemeManager.shared.theme.background
  }

  static var hbSurface: Color {
    ThemeManager.shared.theme.surface
  }

  static var hbSurfaceElevated: Color {
    ThemeManager.shared.theme.surfaceElevated
  }

  static var hbBorder: Color {
    ThemeManager.shared.theme.border
  }

  /// Accents
  static var hbBitcoinOrange: Color {
    ThemeManager.shared.theme.accent
  }

  static let hbSteelBlue = Color(red: 0.290, green: 0.565, blue: 0.851) // #4A90D9 — not themed

  /// Semantic
  static var hbSuccess: Color {
    ThemeManager.shared.theme.success
  }

  static var hbError: Color {
    ThemeManager.shared.theme.error
  }

  /// Text
  static var hbTextPrimary: Color {
    ThemeManager.shared.theme.textPrimary
  }

  static var hbTextSecondary: Color {
    ThemeManager.shared.theme.textSecondary
  }
}

// MARK: - Typography

extension Font {
  static func hbDisplay(_ size: CGFloat) -> Font {
    .system(size: size, weight: .medium, design: .rounded)
  }

  static func hbBody(_ size: CGFloat = 16) -> Font {
    .system(size: size, weight: .regular, design: .default)
  }

  static func hbMono(_ size: CGFloat = 14) -> Font {
    .system(size: size, weight: .regular, design: .monospaced)
  }

  static func hbMonoBold(_ size: CGFloat = 14) -> Font {
    .system(size: size, weight: .bold, design: .monospaced)
  }

  static func hbLabel(_ size: CGFloat = 13) -> Font {
    .system(size: size, weight: .regular, design: .default)
  }

  static let hbAmountLarge: Font = .system(size: 36, weight: .bold, design: .rounded)
  static let hbAmountMedium: Font = .system(size: 24, weight: .semibold, design: .rounded)
  static let hbTitle: Font = .system(size: 20, weight: .medium, design: .rounded)
  static let hbHeadline: Font = .system(size: 17, weight: .semibold, design: .rounded)
}

// MARK: - View Modifiers

struct HBCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(16)
      .background(Color.hbSurface)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(Color.hbBorder, lineWidth: 0.5)
      )
  }
}

struct HBPrimaryButtonModifier: ViewModifier {
  var isEnabled: Bool = true

  func body(content: Content) -> some View {
    content
      .font(.hbHeadline)
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 16)
      .background(isEnabled ? Color.hbBitcoinOrange : Color.hbBorder)
      .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

struct HBSecondaryButtonModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .font(.hbHeadline)
      .foregroundStyle(Color.hbBitcoinOrange)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 16)
      .background(Color.hbSurface)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(Color.hbBitcoinOrange, lineWidth: 1)
      )
  }
}

extension View {
  func hbCard() -> some View {
    modifier(HBCardModifier())
  }

  func hbPrimaryButton(isEnabled: Bool = true) -> some View {
    modifier(HBPrimaryButtonModifier(isEnabled: isEnabled))
  }

  func hbSecondaryButton() -> some View {
    modifier(HBSecondaryButtonModifier())
  }
}

// MARK: - Network Badge

struct NetworkBadge: View {
  let network: BitcoinNetwork

  var badgeColor: Color {
    switch network {
    case .mainnet: .hbBitcoinOrange
    case .testnet4: .hbSteelBlue
    case .testnet3: .hbSteelBlue.opacity(0.7)
    case .signet: .purple
    }
  }

  var body: some View {
    Text(network.displayName)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(badgeColor)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(badgeColor.opacity(0.15))
      .clipShape(Capsule())
  }
}

// MARK: - Sync Status Dot

struct SyncStatusDot: View {
  let state: WalletSyncState

  var color: Color {
    switch state {
    case .notStarted: .hbTextSecondary
    case .syncing: .hbBitcoinOrange
    case .synced: .hbSuccess
    case .error: .hbError
    }
  }

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 8, height: 8)
      .overlay {
        if state.isSyncing {
          Circle()
            .fill(color.opacity(0.3))
            .frame(width: 16, height: 16)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: state.isSyncing)
        }
      }
      .padding(10)
      .background(color.opacity(0.1))
      .clipShape(Circle())
  }
}
