import Foundation
import Observation

@Observable
final class BumpFeeViewModel {
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
    // Pre-fill custom with the minimum valid bump rate
    let minRate = (originalFeeRate.map { Double($0) } ?? 0.0) + 1.0
    newFeeRate = BumpFeeViewModel.formatRate(max(minRate, 1.0))
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

  func handleSignedPSBT(_ signedBytes: Data) async {
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

  func broadcast() async {
    isProcessing = true
    do {
      let txid = try await bitcoinService.broadcastPSBT(psbtBytes)
      broadcastTxid = txid
      // Trigger sync after broadcast
      Task {
        try? await bitcoinService.sync()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
    isProcessing = false
  }
}
