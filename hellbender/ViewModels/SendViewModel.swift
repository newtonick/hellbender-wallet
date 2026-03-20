import Foundation
import Observation
import SwiftData

struct Recipient: Identifiable {
  let id = UUID()
  var address: String = ""
  var amountSats: String = ""
  var isSendMax: Bool = false
  var label: String = ""

  var amountValue: UInt64? {
    UInt64(amountSats)
  }

  var isAddressEmpty: Bool {
    address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var isValidAddress: Bool {
    !isAddressEmpty
  }

  /// Checks if the address looks like a valid Bitcoin address format
  func isAddressFormatValid(network: BitcoinNetwork?) -> Bool {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true } // empty is not "invalid format", just missing
    guard let network else { return true }

    let prefix = network.addressPrefix
    // Accept bech32/bech32m addresses for the current network
    if trimmed.lowercased().hasPrefix(prefix) {
      return trimmed.count >= prefix.count + 10 // minimum reasonable length
    }
    // Also accept legacy P2SH (3...) and P2PKH (1...) on mainnet
    if network == .mainnet, trimmed.hasPrefix("3") || trimmed.hasPrefix("1") {
      return trimmed.count >= 26 && trimmed.count <= 35
    }
    // Accept testnet P2SH (2...) and P2PKH (m.../n...)
    if network != .mainnet, trimmed.hasPrefix("2") || trimmed.hasPrefix("m") || trimmed.hasPrefix("n") {
      return trimmed.count >= 26 && trimmed.count <= 35
    }
    return false
  }

  var isValidAmount: Bool {
    guard let amount = amountValue else { return false }
    return amount > 0
  }

  var isAmountEmpty: Bool {
    amountSats.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

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

@Observable
final class SendViewModel {
  enum Step: Int, CaseIterable {
    case recipients
    case review
    case psbtDisplay
    case psbtScan
    case broadcast
  }

  /// Navigation
  var currentStep: Step = .recipients

  // Input
  var recipients: [Recipient] = [Recipient()]
  var amountInFiat: Bool = false
  var fiatDisplayAmount: [UUID: String] = [:] // per-recipient fiat display strings
  var feeRateSatVb: String = "" // empty until rates load
  var selectedFeePreset: FeePreset = .medium
  var showAddressScanner: Bool = false
  var scanTargetRecipientIndex: Int = 0
  var recommendedFees: BitcoinService.RecommendedFees?

  // UTXO selection
  var manualUTXOSelection: Bool = false
  var selectedUTXOIds: Set<String> = [] // "txid:vout"
  var showUTXOPicker: Bool = false

  /// Validation
  var showValidationErrors: Bool = false

  // State
  var psbtBase64: String = ""
  var psbtBytes: Data = .init()
  var signaturesCollected: Int = 0
  var requiredSignatures: Int = 2
  var totalCosigners: Int = 1
  var broadcastTxid: String = ""
  var finalizedTxBytes: Data = .init()
  var errorMessage: String?
  var isProcessing: Bool = false
  var showExportQR: Bool = false

  // Saved PSBT
  var savedPSBTId: UUID?
  var savedPSBTName: String = ""
  var showSavePSBT: Bool = false
  var showSavedConfirmation: Bool = false
  var showLoadPSBT: Bool = false

  // Import PSBT
  var showImportPSBTQR: Bool = false
  var showImportPSBTFile: Bool = false

  /// Cosigner signing status (populated from PSBT analysis)
  var signerStatus: [(label: String, fingerprint: String, hasSigned: Bool)] = []

  // Transaction details (populated after PSBT creation)
  var totalFee: UInt64 = 0
  var changeAmount: UInt64?
  var changeAddress: String?
  var inputCount: Int = 0

  /// Balance
  var availableBalance: UInt64 = 0

  private let bitcoinService: any BitcoinServiceProtocol

  init(bitcoinService: any BitcoinServiceProtocol = BitcoinService.shared) {
    self.bitcoinService = bitcoinService
  }

  var frozenOutpoints: Set<String> = []

  var allUTXOs: [UTXOItem] {
    bitcoinService.utxos
  }

  var spendableUTXOs: [UTXOItem] {
    bitcoinService.utxos.filter { !frozenOutpoints.contains($0.id) }
  }

  var frozenUTXOs: [UTXOItem] {
    bitcoinService.utxos.filter { frozenOutpoints.contains($0.id) }
  }

  func isFrozen(_ utxo: UTXOItem) -> Bool {
    frozenOutpoints.contains(utxo.id)
  }

  var selectedUTXOTotal: UInt64 {
    guard manualUTXOSelection else { return availableBalance }
    return allUTXOs
      .filter { selectedUTXOIds.contains($0.id) }
      .reduce(0) { $0 + $1.amount }
  }

  var currentNetwork: BitcoinNetwork? {
    bitcoinService.currentNetwork
  }

  var feeRateValue: Double {
    Double(feeRateSatVb) ?? 0
  }

  var isValidFeeRate: Bool {
    feeRateValue > 0
  }

  var hasAnyInput: Bool {
    recipients.contains { !$0.isAddressEmpty || !$0.isAmountEmpty || !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      || manualUTXOSelection
  }

  var hasValidRecipients: Bool {
    !recipients.isEmpty && recipients.allSatisfy { r in
      r.isValidAddress && (r.isValidAmount || (r.isSendMax && r.amountValue != nil))
    }
  }

  /// Check if a send-max recipient has zero amount (blocks review)
  var hasSendMaxZeroAmount: Bool {
    recipients.contains { $0.isSendMax && ($0.amountValue ?? 0) == 0 }
  }

  var isBalanceExceeded: Bool {
    guard !hasSendMax else { return false } // send-max self-adjusts
    let totalAmount = totalSendAmount
    let fee = estimateFee()
    return totalAmount + fee > selectedUTXOTotal
  }

  /// Attempt to proceed to review; builds a draft PSBT to get exact fee/change info
  func tryReview() {
    // If we have a loaded saved PSBT with signatures, go straight to review
    // without rebuilding (which would create a new unsigned PSBT and lose signatures)
    if savedPSBTId != nil, signaturesCollected > 0, !psbtBytes.isEmpty {
      currentStep = .review
      return
    }
    showValidationErrors = true
    guard hasValidRecipients, isValidFeeRate, !isBalanceExceeded, !hasSendMaxZeroAmount else { return }
    guard recipients.allSatisfy({ $0.isAddressFormatValid(network: currentNetwork) }) else { return }
    showValidationErrors = false
    Task { await buildDraftPSBT() }
  }

  var totalSendAmount: UInt64 {
    recipients.reduce(0) { $0 + ($1.amountValue ?? 0) }
  }

  var hasSendMax: Bool {
    recipients.contains { $0.isSendMax }
  }

  /// Build a preview TransactionItem for the send flow detail screen
  var previewTransaction: TransactionItem {
    let outputs = recipients.map { r in
      TransactionItem.TxIO(
        address: r.address.trimmingCharacters(in: .whitespacesAndNewlines),
        amount: r.amountValue ?? 0,
        prevTxid: nil,
        prevVout: nil,
        isMine: false
      )
    }
    return TransactionItem(
      id: broadcastTxid.isEmpty ? "Unsigned" : broadcastTxid,
      amount: -Int64(totalSendAmount),
      fee: nil,
      confirmations: 0,
      timestamp: nil,
      isIncoming: false,
      inputs: [],
      outputs: outputs
    )
  }

  /// Total deducted from wallet = send amount + fee
  var totalSpendAmount: UInt64 {
    totalSendAmount + totalFee
  }

  /// Total sats of all inputs = send amount + fee + change
  var inputsAmount: UInt64 {
    totalSendAmount + totalFee + (changeAmount ?? 0)
  }

  var signatureProgress: String {
    "\(signaturesCollected) of \(requiredSignatures) signatures"
  }

  var needsMoreSignatures: Bool {
    signaturesCollected < requiredSignatures
  }

  func loadBalance() {
    availableBalance = spendableUTXOs.reduce(0) { $0 + $1.amount }
    requiredSignatures = bitcoinService.requiredSignatures
    totalCosigners = bitcoinService.totalCosigners
  }

  // MARK: - Fiat Toggle

  private var fiatService: FiatPriceService {
    FiatPriceService.shared
  }

  var canToggleFiat: Bool {
    fiatService.currentRate != nil
  }

  func toggleAmountCurrency() {
    guard canToggleFiat else { return }

    if amountInFiat {
      // Switching from fiat to sats: convert fiat display amounts back to sats
      for i in recipients.indices {
        if recipients[i].isSendMax { continue }
        let fiatStr = fiatDisplayAmount[recipients[i].id] ?? ""
        if let fiatVal = Double(fiatStr), fiatVal > 0,
           let sats = fiatService.fiatToSats(fiatVal)
        {
          recipients[i].amountSats = "\(sats)"
        }
      }
    } else {
      // Switching from sats to fiat: convert sats to fiat display amounts
      for i in recipients.indices {
        if recipients[i].isSendMax {
          if let sats = recipients[i].amountValue,
             let fiatVal = fiatService.satsToFiat(sats)
          {
            fiatDisplayAmount[recipients[i].id] = String(format: "%.2f", fiatVal)
          }
          continue
        }
        if let sats = recipients[i].amountValue,
           let fiatVal = fiatService.satsToFiat(sats)
        {
          fiatDisplayAmount[recipients[i].id] = String(format: "%.2f", fiatVal)
        } else {
          fiatDisplayAmount[recipients[i].id] = ""
        }
      }
    }

    amountInFiat.toggle()
  }

  /// Called when fiat amount text changes — updates the underlying sats value
  func updateSatsFromFiat(for index: Int) {
    guard amountInFiat, !recipients[index].isSendMax else { return }
    let fiatStr = fiatDisplayAmount[recipients[index].id] ?? ""
    if let fiatVal = Double(fiatStr), fiatVal > 0,
       let sats = fiatService.fiatToSats(fiatVal)
    {
      recipients[index].amountSats = "\(sats)"
    } else {
      recipients[index].amountSats = ""
    }
  }

  // MARK: - Recipients

  var canAddRecipient: Bool {
    !hasSendMax
  }

  func addRecipient() {
    guard canAddRecipient else { return }
    recipients.append(Recipient())
  }

  func removeRecipient(at index: Int) {
    guard recipients.count > 1 else { return }
    let hadMax = recipients[index].isSendMax
    recipients.remove(at: index)
    if hadMax {
      // MAX was on the deleted recipient — clear it entirely
      for i in recipients.indices {
        recipients[i].isSendMax = false
      }
    }
  }

  func toggleUTXOSelection(_ utxoId: String) {
    if selectedUTXOIds.contains(utxoId) {
      selectedUTXOIds.remove(utxoId)
    } else {
      selectedUTXOIds.insert(utxoId)
    }
    recalculateMaxIfNeeded()
  }

  func setManualUTXOSelection(_ enabled: Bool) {
    manualUTXOSelection = enabled
    if !enabled {
      selectedUTXOIds.removeAll()
    }
    recalculateMaxIfNeeded()
  }

  /// MAX is only allowed on the last recipient
  var isMaxAllowed: Bool {
    true // Always allowed on last recipient; UI hides the button for non-last recipients
  }

  func toggleMaxAmount(for index: Int) {
    guard index == recipients.count - 1 else { return } // only last recipient

    // If already max, untoggle and clear
    if recipients[index].isSendMax {
      recipients[index].isSendMax = false
      recipients[index].amountSats = ""
      fiatDisplayAmount[recipients[index].id] = ""
      return
    }
    // Clear any other send-max flags (shouldn't exist, but be safe)
    for i in recipients.indices {
      recipients[i].isSendMax = false
    }
    recipients[index].isSendMax = true
    recalculateMax(for: index)
  }

  func fetchFeeRates() async {
    do {
      let rates = try await bitcoinService.getFeeRates()
      await MainActor.run {
        self.recommendedFees = rates
        applyPreset(selectedFeePreset)
      }
    } catch {
      print("Failed to fetch fee rates: \(error)")
    }
  }

  func applyPreset(_ preset: FeePreset) {
    selectedFeePreset = preset
    if let rate = preset.rate(from: recommendedFees) {
      feeRateSatVb = formatRate(rate)
    }
  }

  private func formatRate(_ rate: Double) -> String {
    var s = String(format: "%.2f", rate)
    if s.contains(".") {
      while s.hasSuffix("0") {
        s.removeLast()
      }
      if s.hasSuffix(".") { s.removeLast() }
    }
    return s
  }

  /// Recalculate the max amount for whichever recipient has isSendMax
  func recalculateMaxIfNeeded() {
    guard let index = recipients.firstIndex(where: { $0.isSendMax }) else { return }
    recalculateMax(for: index)
  }

  private func recalculateMax(for index: Int) {
    let spendableBalance = selectedUTXOTotal
    let otherAmounts = recipients.enumerated()
      .filter { $0.offset != index }
      .reduce(UInt64(0)) { $0 + ($1.element.amountValue ?? 0) }
    let feeEstimate = estimateFee()
    let maxAmount = spendableBalance > (otherAmounts + feeEstimate) ?
      spendableBalance - otherAmounts - feeEstimate : 0
    recipients[index].amountSats = "\(maxAmount)"
    if amountInFiat, let fiatVal = fiatService.satsToFiat(maxAmount) {
      fiatDisplayAmount[recipients[index].id] = String(format: "%.2f", fiatVal)
    }
  }

  func estimateFee() -> UInt64 {
    estimatedFee(for: feeRateValue)
  }

  func estimatedFee(for rate: Double) -> UInt64 {
    // Rough estimate: P2WSH multisig input ~200 vbytes, output ~43 vbytes each, overhead ~10
    let inputCount: Int = if manualUTXOSelection {
      max(selectedUTXOIds.count, 1)
    } else {
      max(bitcoinService.utxos.count, 1)
    }
    let outputCount = recipients.count + 1 // +1 for change
    let estimatedVbytes = UInt64(inputCount * 200 + outputCount * 43 + 10)
    return UInt64(Double(estimatedVbytes) * max(rate, 0.001))
  }

  /// Parse a BIP-21 URI or plain address string
  func parseBIP21(_ input: String, forRecipientAt index: Int) {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

    // Check for BIP-21 URI: bitcoin:address?amount=0.001&label=...
    guard let url = URL(string: trimmed),
          let scheme = url.scheme?.lowercased(),
          scheme == "bitcoin" || scheme == "BITCOIN".lowercased()
    else {
      // Plain address
      recipients[index].address = trimmed
      return
    }

    // Extract address from path
    let address: String
    if let host = url.host(percentEncoded: false), !host.isEmpty {
      address = host
    } else {
      // bitcoin:tb1q... — opaque path
      let stripped = trimmed.drop(while: { $0 != ":" }).dropFirst()
      let addrPart = stripped.prefix(while: { $0 != "?" })
      address = String(addrPart)
    }

    recipients[index].address = address

    // Parse query parameters
    if let components = URLComponents(string: trimmed) {
      for item in components.queryItems ?? [] {
        switch item.name.lowercased() {
        case "amount":
          // BIP-21 amount is in BTC, convert to sats
          if let btcString = item.value, let btc = Double(btcString) {
            let sats = UInt64(btc * 100_000_000)
            recipients[index].amountSats = "\(sats)"
            recipients[index].isSendMax = false
          }
        default:
          break
        }
      }
    }
  }

  // MARK: - PSBT Operations

  /// Build a draft PSBT to populate fee/change details, then navigate to review
  private func buildDraftPSBT() async {
    isProcessing = true
    do {
      let recipientList = recipients.map { r in
        (address: r.address.trimmingCharacters(in: .whitespacesAndNewlines),
         amount: r.amountValue ?? 0,
         isSendMax: r.isSendMax)
      }

      let utxoOutpoints: [(txid: String, vout: UInt32)]? = manualUTXOSelection
        ? allUTXOs.filter { selectedUTXOIds.contains($0.id) }.map { (txid: $0.txid, vout: $0.vout) }
        : nil

      let result = try await bitcoinService.createPSBT(
        recipients: recipientList,
        feeRate: feeRateValue,
        utxos: utxoOutpoints,
        unspendable: frozenOutpoints
      )
      psbtBase64 = result.base64
      psbtBytes = result.bytes
      totalFee = result.fee
      changeAmount = result.changeAmount
      changeAddress = result.changeAddress
      inputCount = result.inputCount
      // Initialize cosigner signing status (all unsigned)
      if let signerInfo = bitcoinService.psbtSignerInfo(result.bytes) {
        signerStatus = signerInfo.cosignerSignStatus
      }
      currentStep = .review
    } catch {
      errorMessage = error.localizedDescription
    }
    isProcessing = false
  }

  func createPSBT() async {
    let recipientList = recipients.map { r in
      (address: r.address.trimmingCharacters(in: .whitespacesAndNewlines),
       amount: r.amountValue ?? 0,
       isSendMax: r.isSendMax)
    }

    guard recipientList.allSatisfy({ !$0.address.isEmpty && ($0.amount > 0 || $0.isSendMax) }) else {
      errorMessage = "Invalid recipient or amount"
      return
    }

    let utxoOutpoints: [(txid: String, vout: UInt32)]? = manualUTXOSelection
      ? allUTXOs.filter { selectedUTXOIds.contains($0.id) }.map { (txid: $0.txid, vout: $0.vout) }
      : nil

    // For manual selection, guard against spending a UTXO the user has frozen.
    // (BDK lets addUtxos() override the unspendable list, so this stays at app layer.)
    if let validationError = validateUTXOInputs(outpoints: utxoOutpoints) {
      errorMessage = validationError
      return
    }

    isProcessing = true
    do {
      let result = try await bitcoinService.createPSBT(
        recipients: recipientList,
        feeRate: feeRateValue,
        utxos: utxoOutpoints,
        unspendable: frozenOutpoints
      )
      psbtBase64 = result.base64
      psbtBytes = result.bytes
      totalFee = result.fee
      changeAmount = result.changeAmount
      changeAddress = result.changeAddress
      inputCount = result.inputCount
      signaturesCollected = 0
      // Initialize cosigner signing status (all unsigned)
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

      // Use PSBT introspection to determine signer status
      if let signerInfo = bitcoinService.psbtSignerInfo(updatedBytes) {
        signaturesCollected = signerInfo.totalSignatures
        signerStatus = signerInfo.cosignerSignStatus
      } else if updatedBytes != previousBytes {
        // Fallback: if psbtSignerInfo unavailable (e.g. no bip32_derivation),
        // increment count based on byte change
        signaturesCollected += 1
      }

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
    guard finalizedTxBytes.isEmpty else { return }
    do {
      finalizedTxBytes = try bitcoinService.finalizePSBTBytes(psbtBytes)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func broadcast() async {
    isProcessing = true
    do {
      let txid = try await bitcoinService.broadcastPSBT(psbtBytes)
      broadcastTxid = txid
      // Trigger sync after broadcast to update wallet state
      Task {
        try? await bitcoinService.sync()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
    isProcessing = false
  }

  /// Validate that no frozen UTXOs are in the input set. Returns an error message if any are found, nil otherwise.
  func validateUTXOInputs(outpoints: [(txid: String, vout: UInt32)]?) -> String? {
    guard let outpoints else { return nil }
    let frozenInInputs = outpoints.filter { frozenOutpoints.contains("\($0.txid):\($0.vout)") }
    if !frozenInInputs.isEmpty {
      return "Cannot create transaction: \(frozenInInputs.count) frozen UTXO(s) in inputs"
    }
    return nil
  }

  // MARK: - Saved PSBT

  func defaultPSBTName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy h:mm a"
    return formatter.string(from: Date())
  }

  func savePSBT(name: String, context: ModelContext) {
    guard let walletID = BitcoinService.shared.currentProfile?.id else { return }

    let trimmedName = String(name.prefix(SavedPSBT.maxNameLength))
    let recipientData = encodeRecipients()

    let utxoIdsString = selectedUTXOIds.sorted().joined(separator: ",")
    let outpoints = bitcoinService.psbtInputOutpoints(psbtBytes).joined(separator: ",")

    if let existingId = savedPSBTId {
      let descriptor = FetchDescriptor<SavedPSBT>(predicate: #Predicate { $0.id == existingId })
      if let existing = try? context.fetch(descriptor).first {
        existing.name = trimmedName
        existing.psbtBytes = psbtBytes
        existing.psbtBase64 = psbtBase64
        existing.signaturesCollected = signaturesCollected
        existing.updatedAt = Date()
        existing.recipientsJSON = recipientData
        existing.feeRateSatVb = feeRateSatVb
        existing.totalFee = totalFee
        existing.changeAmount = changeAmount
        existing.changeAddress = changeAddress
        existing.inputCount = inputCount
        existing.manualUTXOSelection = manualUTXOSelection
        existing.selectedUTXOIds = utxoIdsString
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
      recipientsJSON: recipientData,
      feeRateSatVb: feeRateSatVb,
      totalFee: totalFee,
      changeAmount: changeAmount,
      changeAddress: changeAddress,
      inputCount: inputCount,
      manualUTXOSelection: manualUTXOSelection,
      selectedUTXOIds: utxoIdsString,
      inputOutpoints: outpoints
    )
    context.insert(saved)
    try? context.save()
    savedPSBTId = saved.id
  }

  func autoSavePSBT(context: ModelContext) {
    if savedPSBTId != nil {
      // Always update an existing saved PSBT (e.g. after adding a signature)
      savePSBT(name: savedPSBTName.isEmpty ? defaultPSBTName() : savedPSBTName, context: context)
    } else if totalCosigners > 1 {
      // Auto-create for any multisig wallet (including 1-of-N where M=1 but N>1)
      savePSBT(name: defaultPSBTName(), context: context)
    }
  }

  func loadSavedPSBT(_ saved: SavedPSBT) {
    // Restore recipients
    if let decoded = try? JSONDecoder().decode([SavedRecipient].self, from: saved.recipientsJSON) {
      recipients = decoded.map { sr in
        var r = Recipient()
        r.address = sr.address
        r.amountSats = sr.amountSats
        r.isSendMax = sr.isSendMax
        r.label = sr.label
        return r
      }
    }

    feeRateSatVb = saved.feeRateSatVb
    totalFee = saved.totalFee
    changeAmount = saved.changeAmount
    changeAddress = saved.changeAddress
    inputCount = saved.inputCount
    psbtBytes = saved.psbtBytes
    psbtBase64 = saved.psbtBase64
    signaturesCollected = saved.signaturesCollected
    requiredSignatures = saved.requiredSignatures
    manualUTXOSelection = saved.manualUTXOSelection
    if !saved.selectedUTXOIds.isEmpty {
      selectedUTXOIds = Set(saved.selectedUTXOIds.split(separator: ",").map(String.init))
    } else {
      selectedUTXOIds = []
    }
    savedPSBTId = saved.id
    savedPSBTName = saved.name

    // Populate cosigner signing status from PSBT
    if let signerInfo = bitcoinService.psbtSignerInfo(saved.psbtBytes) {
      signaturesCollected = signerInfo.totalSignatures
      signerStatus = signerInfo.cosignerSignStatus
    }

    currentStep = .review
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

  // MARK: - Import PSBT

  func importPSBT(_ psbtData: Data, source: String, context: ModelContext) {
    do {
      let result = try bitcoinService.validateAndParseImportedPSBT(psbtData, frozenOutpoints: frozenOutpoints)

      // Populate view model state from parsed PSBT
      recipients = result.recipients.map { sr in
        var r = Recipient()
        r.address = sr.address
        r.amountSats = sr.amountSats
        r.isSendMax = sr.isSendMax
        r.label = sr.label
        return r
      }

      feeRateSatVb = result.feeRateSatVb
      totalFee = result.fee
      changeAmount = result.changeAmount
      changeAddress = result.changeAddress
      inputCount = result.inputCount
      psbtBytes = result.psbtBytes
      psbtBase64 = result.psbtBase64
      requiredSignatures = bitcoinService.requiredSignatures
      totalCosigners = bitcoinService.totalCosigners

      // Determine signature status
      if let signerInfo = bitcoinService.psbtSignerInfo(result.psbtBytes) {
        signaturesCollected = signerInfo.totalSignatures
        signerStatus = signerInfo.cosignerSignStatus
      } else {
        signaturesCollected = 0
        signerStatus = []
      }

      // Save immediately
      let importName = "Imported via \(source) \(defaultPSBTName())"
      savePSBT(name: importName, context: context)
      savedPSBTName = importName

      // Navigate to review
      currentStep = .review
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func encodeRecipients() -> Data {
    let savedRecipients = recipients.map { r in
      SavedRecipient(
        address: r.address.trimmingCharacters(in: .whitespacesAndNewlines),
        amountSats: r.amountSats,
        isSendMax: r.isSendMax,
        label: r.label
      )
    }
    return (try? JSONEncoder().encode(savedRecipients)) ?? Data()
  }

  func reset() {
    currentStep = .recipients
    recipients = [Recipient()]
    amountInFiat = false
    fiatDisplayAmount.removeAll()
    selectedFeePreset = .medium
    applyPreset(.medium)
    psbtBase64 = ""
    psbtBytes = Data()
    totalFee = 0
    changeAmount = nil
    changeAddress = nil
    inputCount = 0
    signaturesCollected = 0
    signerStatus = []
    broadcastTxid = ""
    finalizedTxBytes = Data()
    errorMessage = nil
    isProcessing = false
    showValidationErrors = false
    showExportQR = false
    showAddressScanner = false
    manualUTXOSelection = false
    selectedUTXOIds.removeAll()
    showUTXOPicker = false
    savedPSBTId = nil
    savedPSBTName = ""
    showSavePSBT = false
    showSavedConfirmation = false
    showLoadPSBT = false
    showImportPSBTQR = false
    showImportPSBTFile = false
  }
}
