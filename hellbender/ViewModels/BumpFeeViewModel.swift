import Foundation
import Observation
import SwiftData

@Observable
final class BumpFeeViewModel: Identifiable {
  let id = UUID()
  enum Step {
    case feeInput
    case psbtDisplay
    case psbtScan
    case broadcast
  }

  /// Navigation
  var currentStep: Step = .feeInput

  // Original transaction context
  let originalTxid: String
  let originalFee: UInt64
  let originalFeeRate: Float?

  // Fee input
  var newFeeRate: String = ""
  var selectedFeePreset: FeePreset = .custom
  var recommendedFees: BitcoinService.RecommendedFees?

  // PSBT state
  var psbtBase64: String = ""
  var psbtBytes: Data = .init()
  var signaturesCollected: Int = 0
  var requiredSignatures: Int = 2
  var signerStatus: [(label: String, fingerprint: String, hasSigned: Bool)] = []

  // Transaction detail state (populated from createBumpFeePSBT result)
  var totalFee: UInt64 = 0
  var changeAmount: UInt64?
  var changeAddress: String?
  var inputCount: Int = 0

  // Saved PSBT state
  var savedPSBTId: UUID?
  var savedPSBTName: String = ""
  var totalCosigners: Int = 1
  var showSavePSBT: Bool = false
  var showSavedConfirmation: Bool = false

  // Broadcast state
  var broadcastTxid: String = ""
  var errorMessage: String?
  var isProcessing: Bool = false

  private let bitcoinService: any BitcoinServiceProtocol

  var feeRateValue: Double {
    Double(newFeeRate) ?? 0
  }

  /// Minimum fee rate (sat/vB) required to replace the original transaction.
  var minimumBumpRate: Double {
    Double(originalFeeRate ?? 0) + 1.0
  }

  var isValidFeeRate: Bool {
    guard let rate = Double(newFeeRate), rate > 0 else { return false }
    if let original = originalFeeRate {
      return rate > Double(original)
    }
    return true
  }

  static func formatRate(_ rate: Double) -> String {
    var s = String(format: "%.2f", rate)
    if s.contains(".") {
      while s.hasSuffix("0") {
        s.removeLast()
      }
      if s.hasSuffix(".") { s.removeLast() }
    }
    return s
  }

  func applyPreset(_ preset: FeePreset) {
    selectedFeePreset = preset
    if let fees = recommendedFees, let rate = preset.rate(from: fees) {
      newFeeRate = Self.formatRate(rate)
    }
    // For .custom, preserve the existing newFeeRate value
  }

  var needsMoreSignatures: Bool {
    signaturesCollected < requiredSignatures
  }

  var signatureProgress: String {
    "\(signaturesCollected) of \(requiredSignatures) signatures"
  }

  init(transaction: TransactionItem, bitcoinService: any BitcoinServiceProtocol = BitcoinService.shared) {
    originalTxid = transaction.id
    originalFee = transaction.fee ?? 0
    originalFeeRate = transaction.currentFeeRate
    self.bitcoinService = bitcoinService
    requiredSignatures = bitcoinService.requiredSignatures
    totalCosigners = bitcoinService.totalCosigners
    // Pre-fill custom with the minimum valid bump rate
    let minRate = (originalFeeRate.map { Double($0) } ?? 0.0) + 1.0
    newFeeRate = BumpFeeViewModel.formatRate(max(minRate, 1.0))
  }

  /// Initialize from a saved RBF PSBT to resume signing
  init(savedPSBT: SavedPSBT, bitcoinService: any BitcoinServiceProtocol = BitcoinService.shared) {
    originalTxid = savedPSBT.originalTxid ?? ""
    originalFee = 0
    originalFeeRate = nil
    self.bitcoinService = bitcoinService
    requiredSignatures = savedPSBT.requiredSignatures
    totalCosigners = bitcoinService.totalCosigners
    newFeeRate = savedPSBT.feeRateSatVb
    psbtBytes = savedPSBT.psbtBytes
    psbtBase64 = savedPSBT.psbtBase64
    totalFee = savedPSBT.totalFee
    changeAmount = savedPSBT.changeAmount
    changeAddress = savedPSBT.changeAddress
    inputCount = savedPSBT.inputCount
    savedPSBTId = savedPSBT.id
    savedPSBTName = savedPSBT.name

    if let signerInfo = bitcoinService.psbtSignerInfo(savedPSBT.psbtBytes) {
      signaturesCollected = signerInfo.totalSignatures
      signerStatus = signerInfo.cosignerSignStatus
    } else {
      signaturesCollected = savedPSBT.signaturesCollected
    }

    currentStep = .psbtDisplay
  }

  func fetchFeeRates() async {
    do {
      let rates = try await bitcoinService.getFeeRates()
      await MainActor.run {
        self.recommendedFees = rates
      }
    } catch {
      print("Failed to fetch fee rates: \(error)")
    }
  }

  func createBumpPSBT() async {
    guard isValidFeeRate else {
      errorMessage = "Fee rate must be higher than the original (\(String(format: "%.1f", originalFeeRate ?? 0)) sat/vB)"
      return
    }

    isProcessing = true
    do {
      let result = try await bitcoinService.createBumpFeePSBT(
        txid: originalTxid,
        feeRate: feeRateValue
      )
      psbtBase64 = result.base64
      psbtBytes = result.bytes
      totalFee = result.fee
      changeAmount = result.changeAmount
      changeAddress = result.changeAddress
      inputCount = result.inputCount
      signaturesCollected = 0
      if let signerInfo = bitcoinService.psbtSignerInfo(result.bytes) {
        signerStatus = signerInfo.cosignerSignStatus
      }
      currentStep = .psbtDisplay
    } catch {
      errorMessage = error.localizedDescription
    }
    isProcessing = false
  }

  func handleSignedPSBT(_ signedBytes: Data, modelContext: ModelContext? = nil) async {
    isProcessing = true
    do {
      let previousBytes = psbtBytes
      let (updatedBase64, updatedBytes) = try await bitcoinService.combinePSBTs(
        original: psbtBytes,
        signed: signedBytes
      )
      psbtBase64 = updatedBase64
      psbtBytes = updatedBytes

      // Use PSBT introspection to determine signature count
      if let signerInfo = bitcoinService.psbtSignerInfo(updatedBytes) {
        signaturesCollected = signerInfo.totalSignatures
        signerStatus = signerInfo.cosignerSignStatus
      } else if updatedBytes != previousBytes {
        signaturesCollected += 1
      }

      // Auto-save after each new signature, matching normal send flow
      if updatedBytes != previousBytes, let context = modelContext {
        autoSavePSBT(context: context)
      }

      if needsMoreSignatures {
        currentStep = .psbtDisplay
      } else {
        currentStep = .broadcast
      }
    } catch {
      errorMessage = error.localizedDescription
    }
    isProcessing = false
  }

  func finalizeTx() {
    do {
      _ = try bitcoinService.finalizePSBTBytes(psbtBytes)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func broadcast(modelContext: ModelContext? = nil) async {
    isProcessing = true
    do {
      let txid = try await bitcoinService.broadcastPSBT(psbtBytes)
      broadcastTxid = txid
      // Clean up saved PSBT after successful broadcast
      if let context = modelContext {
        deleteSavedPSBT(context: context)
      }
      // Trigger sync after broadcast
      Task {
        try? await bitcoinService.sync()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
    isProcessing = false
  }

  // MARK: - Saved PSBT

  func defaultPSBTName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy h:mm a"
    return "Bump Fee " + formatter.string(from: Date())
  }

  func autoSavePSBT(context: ModelContext) {
    if savedPSBTId != nil {
      savePSBT(name: savedPSBTName.isEmpty ? defaultPSBTName() : savedPSBTName, context: context)
    } else if totalCosigners > 1 {
      savePSBT(name: defaultPSBTName(), context: context)
    }
  }

  func savePSBT(name: String, context: ModelContext) {
    guard let walletID = BitcoinService.shared.currentProfile?.id else { return }

    let trimmedName = String(name.prefix(SavedPSBT.maxNameLength))
    let outpoints = bitcoinService.psbtInputOutpoints(psbtBytes).joined(separator: ",")

    if let existingId = savedPSBTId {
      let descriptor = FetchDescriptor<SavedPSBT>(predicate: #Predicate { $0.id == existingId })
      if let existing = try? context.fetch(descriptor).first {
        existing.name = trimmedName
        existing.psbtBytes = psbtBytes
        existing.psbtBase64 = psbtBase64
        existing.signaturesCollected = signaturesCollected
        existing.updatedAt = Date()
        existing.feeRateSatVb = newFeeRate
        existing.totalFee = totalFee
        existing.changeAmount = changeAmount
        existing.changeAddress = changeAddress
        existing.inputCount = inputCount
        existing.inputOutpoints = outpoints
        try? context.save()
        return
      }
    }

    let saved = SavedPSBT(
      walletID: walletID,
      name: trimmedName,
      psbtBytes: psbtBytes,
      psbtBase64: psbtBase64,
      signaturesCollected: signaturesCollected,
      requiredSignatures: requiredSignatures,
      recipientsJSON: Data(),
      feeRateSatVb: newFeeRate,
      totalFee: totalFee,
      changeAmount: changeAmount,
      changeAddress: changeAddress,
      inputCount: inputCount,
      manualUTXOSelection: false,
      selectedUTXOIds: "",
      inputOutpoints: outpoints
    )
    saved.originalTxid = originalTxid
    context.insert(saved)
    try? context.save()
    savedPSBTId = saved.id
    savedPSBTName = trimmedName
  }

  func deleteSavedPSBT(context: ModelContext) {
    guard let existingId = savedPSBTId else { return }
    let descriptor = FetchDescriptor<SavedPSBT>(predicate: #Predicate { $0.id == existingId })
    if let existing = try? context.fetch(descriptor).first {
      context.delete(existing)
      try? context.save()
    }
    savedPSBTId = nil
  }
}
