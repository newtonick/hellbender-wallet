import Foundation

enum FeePreset: CaseIterable {
  case fast, medium, slow, custom

  var displayName: String {
    switch self {
    case .fast: "Fast"
    case .medium: "Medium"
    case .slow: "Slow"
    case .custom: "Custom"
    }
  }

  func rate(from fees: BitcoinService.RecommendedFees?) -> Double? {
    guard let fees else { return nil }
    switch self {
    case .fast: return fees.fast
    case .medium: return fees.medium
    case .slow: return fees.slow
    case .custom: return nil
    }
  }
}
