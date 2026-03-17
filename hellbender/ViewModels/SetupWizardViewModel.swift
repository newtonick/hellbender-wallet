import Foundation
import Observation
import SwiftData

@Observable
final class SetupWizardViewModel {
  enum Step: Int, CaseIterable {
    case welcome
    case creationChoice
    case multisigConfig
    case cosignerImport
    case descriptorImport
    case walletName
    case review
  }

  enum CreationMode {
    case createNew
    case importDescriptor
  }

  // Navigation
  var currentStep: Step = .welcome
  var creationMode: CreationMode = .createNew

  // Multisig config
  var requiredSignatures: Int = 2
  var totalCosigners: Int = 3

  // Cosigner data
  var cosignerLabels: [String] = []
  var cosignerXpubs: [String] = []
  var cosignerFingerprints: [String] = []
  var cosignerDerivationPaths: [String] = []
  var currentCosignerIndex: Int = 0

  /// Import
  var importedDescriptorText: String = ""

  /// Wallet name
  var walletName: String = ""

  // Computed descriptors
  var externalDescriptor: String = ""
  var internalDescriptor: String = ""

  // Electrum server
  var electrumHost: String = ""
  var electrumPort: String = ""
  var electrumSSL: Int = 0 // 0 = network default, 1 = TCP, 2 = SSL

  var isElectrumHostRequired: Bool {
    network.defaultElectrumHost == nil
  }

  var isElectrumHostValid: Bool {
    !isElectrumHostRequired || !electrumHost.trimmingCharacters(in: .whitespaces).isEmpty
  }

  // Advanced settings
  var blockExplorerHost: String = ""
  var addressGapLimit: String = "50"

  // State
  var errorMessage: String?
  var isProcessing: Bool = false
  var network: BitcoinNetwork = .testnet4

  /// Progress
  var stepCount: Int {
    creationMode == .createNew ? 5 : 4
  }

  var currentStepIndex: Int {
    switch currentStep {
    case .welcome: 0
    case .creationChoice: 1
    case .multisigConfig: 2
    case .cosignerImport: 3
    case .descriptorImport: 2
    case .walletName: creationMode == .createNew ? 4 : 3
    case .review: stepCount - 1
    }
  }

  var progress: Double {
    Double(currentStepIndex) / Double(stepCount - 1)
  }

  // MARK: - Cosigner Management

  func initializeCosigners() {
    let count = totalCosigners
    cosignerLabels = (0 ..< count).map { "Cosigner \($0 + 1)" }
    cosignerXpubs = Array(repeating: "", count: count)
    cosignerFingerprints = Array(repeating: "", count: count)
    cosignerDerivationPaths = Array(repeating: Constants.derivationPath(for: network), count: count)
    currentCosignerIndex = 0
  }

  var allCosignersComplete: Bool {
    cosignerXpubs.allSatisfy { !$0.isEmpty }
      && cosignerFingerprints.allSatisfy { !$0.isEmpty }
  }

  var currentCosignerComplete: Bool {
    guard currentCosignerIndex < cosignerXpubs.count else { return false }
    return !cosignerXpubs[currentCosignerIndex].isEmpty
      && !cosignerFingerprints[currentCosignerIndex].isEmpty
  }

  // MARK: - Validation

  func validateCosignerXpub(_ xpub: String, at index: Int) -> String? {
    if xpub.isEmpty { return "Xpub is required" }

    let expectedPrefixes = network == .mainnet ? ["xpub", "Zpub"] : ["tpub", "Vpub"]
    if !expectedPrefixes.contains(where: { xpub.hasPrefix($0) }) {
      return "Expected \(expectedPrefixes.joined(separator: " or ")) prefix for \(network.displayName)"
    }

    // Check for duplicates
    for (i, existing) in cosignerXpubs.enumerated() where i != index {
      if !existing.isEmpty, existing == xpub {
        return "Duplicate xpub (same as Cosigner \(i + 1))"
      }
    }

    return nil
  }

  func validateFingerprint(_ fp: String) -> String? {
    if fp.isEmpty { return "Fingerprint is required" }
    if fp.count != 8 { return "Fingerprint must be 8 hex characters" }
    if !fp.allSatisfy(\.isHexDigit) { return "Fingerprint must be hex characters only" }
    return nil
  }

  // MARK: - Descriptor Building

  func buildDescriptors() {
    guard allCosignersComplete else { return }

    // Build key origin strings and sort by xpub (BIP67 lexicographic sort)
    var keyEntries: [(origin: String, xpub: String, fingerprint: String, path: String, label: String, index: Int)] = []

    for i in 0 ..< totalCosigners {
      keyEntries.append((
        origin: "[\(cosignerFingerprints[i])/48'/\(network.coinType)'/0'/2']",
        xpub: cosignerXpubs[i],
        fingerprint: cosignerFingerprints[i],
        path: cosignerDerivationPaths[i],
        label: cosignerLabels[i],
        index: i
      ))
    }

    // Sort by xpub for BIP67 compliance
    keyEntries.sort { $0.xpub < $1.xpub }

    let externalKeys = keyEntries.map {
      let xpub = $0.xpub.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      return "\($0.origin)\(xpub)/0/*"
    }.joined(separator: ",")
    let internalKeys = keyEntries.map {
      let xpub = $0.xpub.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      return "\($0.origin)\(xpub)/1/*"
    }.joined(separator: ",")

    externalDescriptor = "wsh(sortedmulti(\(requiredSignatures),\(externalKeys)))"
    internalDescriptor = "wsh(sortedmulti(\(requiredSignatures),\(internalKeys)))"
  }

  func parseImportedDescriptor() -> Bool {
    var text = importedDescriptorText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      errorMessage = "Descriptor is empty"
      return false
    }

    // Strip checksum (e.g. #2kjudevd)
    if let hashIndex = text.lastIndex(of: "#") {
      text = String(text[text.startIndex ..< hashIndex])
    }

    // Normalize hardened notation: h → '
    text = text.replacingOccurrences(of: "h/", with: "'/")
    text = text.replacingOccurrences(of: "h]", with: "']")
    text = text.replacingOccurrences(of: "h)", with: "')")

    // Basic validation - check it starts with wsh(sortedmulti(
    guard text.hasPrefix("wsh(sortedmulti(") else {
      errorMessage = "Descriptor must be wsh(sortedmulti(...)) format"
      return false
    }

    // Extract M value
    let afterPrefix = text.dropFirst("wsh(sortedmulti(".count)
    guard let commaIndex = afterPrefix.firstIndex(of: ",") else {
      errorMessage = "Cannot parse M value from descriptor"
      return false
    }
    guard let m = Int(afterPrefix[afterPrefix.startIndex ..< commaIndex]) else {
      errorMessage = "Invalid M value"
      return false
    }

    // Handle BIP-389 multipath descriptors: /<0;1>/* → split into /0/* and /1/*
    if text.contains("<0;1>/*") {
      externalDescriptor = text.replacingOccurrences(of: "<0;1>/*", with: "0/*")
      internalDescriptor = text.replacingOccurrences(of: "<0;1>/*", with: "1/*")
    } else if text.contains("<1;0>/*") {
      externalDescriptor = text.replacingOccurrences(of: "<1;0>/*", with: "0/*")
      internalDescriptor = text.replacingOccurrences(of: "<1;0>/*", with: "1/*")
    } else {
      // Standard single-path descriptor
      let isExternal = text.contains("/0/*")
      if isExternal {
        externalDescriptor = text
        internalDescriptor = text.replacingOccurrences(of: "/0/*", with: "/1/*")
      } else {
        internalDescriptor = text
        externalDescriptor = text.replacingOccurrences(of: "/1/*", with: "/0/*")
      }
    }

    // Parse cosigner info from key origins
    // Supports both ' and h for hardened notation (already normalized to ' above)
    let pattern = #"\[([0-9a-fA-F]{8})/48'/([01])'/(\d+)'/2'\]([xt]pub[a-zA-Z0-9]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      errorMessage = "Failed to parse cosigner keys"
      return false
    }

    let nsText = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

    if matches.isEmpty {
      errorMessage = "No cosigner keys found in descriptor"
      return false
    }

    requiredSignatures = m
    totalCosigners = matches.count

    cosignerLabels = []
    cosignerXpubs = []
    cosignerFingerprints = []
    cosignerDerivationPaths = []

    for (i, match) in matches.enumerated() {
      let fp = nsText.substring(with: match.range(at: 1))
      let coin = nsText.substring(with: match.range(at: 2))
      let account = nsText.substring(with: match.range(at: 3))
      let xpub = nsText.substring(with: match.range(at: 4))

      cosignerLabels.append("Cosigner \(i + 1)")
      cosignerFingerprints.append(fp)
      cosignerXpubs.append(xpub)
      cosignerDerivationPaths.append("m/48'/\(coin)'/\(account)'/2'")
    }

    if requiredSignatures > totalCosigners {
      errorMessage = "M (\(requiredSignatures)) cannot be greater than N (\(totalCosigners))"
      return false
    }

    return true
  }

  // MARK: - Navigation

  func goToNext() {
    switch currentStep {
    case .welcome:
      currentStep = .creationChoice
    case .creationChoice:
      if creationMode == .createNew {
        currentStep = .multisigConfig
      } else {
        currentStep = .descriptorImport
      }
    case .multisigConfig:
      guard isElectrumHostValid else {
        errorMessage = "An Electrum server host is required for \(network.displayName)"
        return
      }
      initializeCosigners()
      currentStep = .cosignerImport
    case .cosignerImport:
      buildDescriptors()
      currentStep = .walletName
    case .descriptorImport:
      guard isElectrumHostValid else {
        errorMessage = "An Electrum server host is required for \(network.displayName)"
        return
      }
      if parseImportedDescriptor() {
        currentStep = .walletName
      }
    case .walletName:
      currentStep = .review
    case .review:
      break // handled by saveWallet
    }
  }

  func goBack() {
    switch currentStep {
    case .welcome: break
    case .creationChoice: currentStep = .welcome
    case .multisigConfig: currentStep = .creationChoice
    case .cosignerImport: currentStep = .multisigConfig
    case .descriptorImport: currentStep = .creationChoice
    case .walletName:
      currentStep = creationMode == .createNew ? .cosignerImport : .descriptorImport
    case .review: currentStep = .walletName
    }
  }

  // MARK: - Save

  func saveWallet(modelContext: ModelContext) throws {
    guard isElectrumHostValid else {
      throw AppError.electrumConnectionFailed("An Electrum server host is required for \(network.displayName)")
    }

    // Deactivate all existing wallets
    let fetchDescriptor = FetchDescriptor<WalletProfile>()
    let existingWallets = try modelContext.fetch(fetchDescriptor)
    for wallet in existingWallets {
      wallet.isActive = false
    }

    // Create new wallet
    let profile = WalletProfile(
      name: walletName.isEmpty ? "My Wallet" : walletName,
      requiredSignatures: requiredSignatures,
      totalCosigners: totalCosigners,
      externalDescriptor: externalDescriptor,
      internalDescriptor: internalDescriptor,
      network: network,
      isActive: true,
      addressGapLimit: Int(addressGapLimit) ?? 50,
      electrumHost: electrumHost.trimmingCharacters(in: .whitespaces),
      electrumPort: Int(electrumPort) ?? 0,
      electrumSSL: electrumSSL,
      blockExplorerHost: blockExplorerHost.trimmingCharacters(in: .whitespaces)
    )

    modelContext.insert(profile)

    // Create cosigner records
    for i in 0 ..< totalCosigners {
      let cosigner = CosignerInfo(
        label: cosignerLabels[i],
        xpub: cosignerXpubs[i],
        fingerprint: cosignerFingerprints[i],
        derivationPath: cosignerDerivationPaths[i],
        orderIndex: i
      )
      cosigner.wallet = profile
      modelContext.insert(cosigner)
    }

    try modelContext.save()

    // Store active wallet ID
    UserDefaults.standard.set(profile.id.uuidString, forKey: Constants.activeWalletIDKey)
    UserDefaults.standard.set(true, forKey: Constants.hasCompletedOnboardingKey)
  }
}
