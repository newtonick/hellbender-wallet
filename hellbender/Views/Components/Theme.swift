import SwiftUI

// MARK: - Color Palette

extension Color {
  // Backgrounds
  static let hbBackground = Color(red: 0.039, green: 0.039, blue: 0.059) // #0A0A0F
  static let hbSurface = Color(red: 0.082, green: 0.082, blue: 0.098) // #151519
  static let hbSurfaceElevated = Color(red: 0.110, green: 0.110, blue: 0.141) // #1C1C24
  static let hbBorder = Color(red: 0.165, green: 0.165, blue: 0.208) // #2A2A35

  // Accents
  static let hbBitcoinOrange = Color(red: 0.969, green: 0.576, blue: 0.102) // #F7931A
  static let hbSteelBlue = Color(red: 0.290, green: 0.565, blue: 0.851) // #4A90D9

  // Semantic
  static let hbSuccess = Color(red: 0.176, green: 0.545, blue: 0.341) // #2D8B57
  static let hbError = Color(red: 0.851, green: 0.267, blue: 0.267) // #D94444

  // Text
  static let hbTextPrimary = Color(red: 0.910, green: 0.902, blue: 0.890) // #E8E6E3
  static let hbTextSecondary = Color(red: 0.420, green: 0.420, blue: 0.463) // #6B6B76
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
