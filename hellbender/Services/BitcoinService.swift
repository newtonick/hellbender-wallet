import BitcoinDevKit
import Combine
import Foundation
import SwiftData

@Observable
final class BitcoinService {
  static let shared = BitcoinService()

  private(set) var wallet: Wallet?
  private var persister: Persister?
  private var electrumClient: ElectrumClient?
  private(set) var currentProfile: WalletProfile?
  var modelContainer: ModelContainer?

  var currentNetwork: BitcoinNetwork? {
    currentProfile?.bitcoinNetwork
  }

  private(set) var balance: UInt64 = 0
  private(set) var transactions: [TransactionItem] = []
  private(set) var utxos: [UTXOItem] = []
  private(set) var requiredSignatures: Int = 2
  private(set) var chainTipHeight: UInt32 = 0
  private var needsFullScan: Bool = true

  // Sync state — single source of truth
  private(set) var syncState: WalletSyncState = .notStarted
  private(set) var lastSyncDate: Date?
  private(set) var lastSyncType: SyncType = .none
  private(set) var syncLog: [String] = []

  private func addToLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let entry = "[\(timestamp)] \(message)"
    print(entry)
    syncLog.append(entry)
    if syncLog.count > 100 {
      syncLog.removeFirst()
    }
  }

  var timeSinceLastSync: TimeInterval {
    guard let lastSyncDate else { return .infinity }
    return Date().timeIntervalSince(lastSyncDate)
  }

  // MARK: - Auto Sync

  private var autoSyncCancellable: AnyCancellable?

  func startAutoSync() {
    guard autoSyncCancellable == nil else { return }
    autoSyncCancellable = Timer.publish(every: 60, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        guard let self, !self.syncState.isSyncing, wallet != nil else { return }
        Task {
          try? await self.sync()
        }
      }
  }

  func stopAutoSync() {
    autoSyncCancellable?.cancel()
    autoSyncCancellable = nil
  }

  func restartAutoSync() {
    stopAutoSync()
    startAutoSync()
  }

  /// Check if enough time has passed since last sync and sync if needed
  func autoSyncIfNeeded() {
    guard !syncState.isSyncing, wallet != nil else { return }
    if timeSinceLastSync >= 60 {
      Task {
        try? await self.sync()
      }
    }
  }

  var isElectrumConnected: Bool {
    electrumClient != nil
  }

  var electrumURL: String? {
    guard let profile = currentProfile else { return nil }
    return profile.electrumConfig.url
  }

  private init() {}

  // MARK: - Wallet Lifecycle

  func loadWallet(profile: WalletProfile) async throws {
    let network = bdkNetwork(from: profile.bitcoinNetwork)
    addToLog("Loading wallet for profile: \(profile.name) (\(profile.id)) on \(profile.bitcoinNetwork.displayName)")

    // Auto-repair malformed descriptors (e.g. double slashes from trailing-slash xpubs)
    let extDescStr = profile.externalDescriptor.replacingOccurrences(of: "//", with: "/")
    let intDescStr = profile.internalDescriptor.replacingOccurrences(of: "//", with: "/")
    if extDescStr != profile.externalDescriptor || intDescStr != profile.internalDescriptor {
      addToLog("Auto-repaired malformed descriptors (double slashes)")
      print("Auto-repaired malformed descriptors (double slashes)")
      profile.externalDescriptor = extDescStr
      profile.internalDescriptor = intDescStr
      // Descriptor changed — delete stale BDK database so wallet is recreated
      let staleDbPath = Constants.walletDatabasePath(for: profile.id)
      try? FileManager.default.removeItem(at: staleDbPath)
    }

    let walletDir = Constants.walletDirectory(for: profile.id)
    try FileManager.default.createDirectory(at: walletDir, withIntermediateDirectories: true)

    let dbPath = Constants.walletDatabasePath(for: profile.id)
    let persister = try Persister.newSqlite(path: dbPath.path)

    let externalDesc = try Descriptor(descriptor: extDescStr, network: network)
    let changeDesc = try Descriptor(descriptor: intDescStr, network: network)

    // Try loading existing wallet first, create new if not found
    let w: Wallet
    do {
      w = try Wallet.load(descriptor: externalDesc, changeDescriptor: changeDesc, persister: persister)
      addToLog("Existing wallet loaded from database")
    } catch {
      // No persisted wallet — create fresh
      addToLog("Creating new wallet instance")
      w = try Wallet(
        descriptor: externalDesc,
        changeDescriptor: changeDesc,
        network: network,
        persister: persister
      )
      // Reveal address #0 for both keychains so incremental syncs always cover it.
      // Without this, startSyncWithRevealedSpks() has nothing to sync against on a
      // brand-new wallet, and any funds sent to the first receive address are missed.
      _ = w.revealNextAddress(keychain: .external)
      _ = w.revealNextAddress(keychain: .internal)
      _ = try w.persist(persister: persister)
      addToLog("Revealed address #0 for external and internal keychains")
    }

    // Full scan only if last full scan was over 1 hour ago (or never)
    let fullScanKey = "lastFullScanDate_\(profile.id.uuidString)"
    let lastFullScan = UserDefaults.standard.object(forKey: fullScanKey) as? Date
    let hoursSinceFullScan = lastFullScan.map { Date().timeIntervalSince($0) / 3600 }
    needsFullScan = (hoursSinceFullScan ?? .infinity) >= 1.0
    addToLog("Full scan needed: \(needsFullScan) (last: \(lastFullScan?.description ?? "never"))")
    syncState = .notStarted
    lastSyncType = .none

    wallet = w
    self.persister = persister
    currentProfile = profile
    requiredSignatures = profile.requiredSignatures

    // Load cached data from persisted wallet first (works offline)
    updateCachedData()

    // Connect to Electrum — may fail offline, but wallet data is still available
    let config = profile.electrumConfig
    addToLog("Connecting to Electrum: \(config.url)")
    do {
      electrumClient = try ElectrumClient(url: config.url)
      addToLog("Electrum client initialized")
    } catch {
      electrumClient = nil
      addToLog("Electrum connection failed: \(error)")
      print("Electrum connection failed (offline?): \(error)")
    }
  }

  // MARK: - Sync

  func sync() async throws {
    guard let wallet else {
      addToLog("Sync failed: Wallet not loaded")
      throw AppError.walletNotLoaded
    }

    syncState = .syncing("Connecting…")
    addToLog("Starting sync (needsFullScan: \(needsFullScan))")

    do {
      // Try to reconnect if client is nil (e.g. app started offline)
      if electrumClient == nil, let profile = currentProfile {
        let config = profile.electrumConfig
        addToLog("Re-initializing Electrum client: \(config.url)")
        electrumClient = try ElectrumClient(url: config.url)
      }

      guard let client = electrumClient else {
        addToLog("Sync failed: No Electrum client")
        throw AppError.electrumConnectionFailed("No internet connection")
      }

      if needsFullScan {
        let gapLimit = currentProfile?.addressGapLimit ?? Constants.maxAddressGap
        addToLog("Starting full scan (gapLimit: \(gapLimit))")

        let inspector = FullScanProgressInspector { [weak self] keychain, index in
          let path = keychain == .external ? "0" : "1"
          self?.syncState = .syncing("Scanning …/\(path)/\(index)")
        }
        let fullScanRequest = try wallet.startFullScan()
          .inspectSpksForAllKeychains(inspector: inspector)
          .build()

        addToLog("Full scan request built")
        syncState = .syncing("Scanning addresses…")
        let update = try client.fullScan(
          request: fullScanRequest,
          stopGap: UInt64(gapLimit),
          batchSize: 50,
          fetchPrevTxouts: true
        )
        addToLog("Full scan update received from server")
        syncState = .syncing("Applying update…")
        try wallet.applyUpdate(update: update)
        addToLog("Full scan update applied to wallet")
        needsFullScan = false
        lastSyncType = .fullScan
        if let profileId = currentProfile?.id {
          UserDefaults.standard.set(Date(), forKey: "lastFullScanDate_\(profileId.uuidString)")
        }
      } else {
        addToLog("Starting incremental sync")

        let inspector = SyncProgressInspector { [weak self] _, total in
          self?.syncState = .syncing("Checking \(total) scripts…")
        }
        let syncRequest = try wallet.startSyncWithRevealedSpks()
          .inspectSpks(inspector: inspector)
          .build()

        addToLog("Sync request built")
        syncState = .syncing("Refreshing transactions…")
        let update = try client.sync(
          request: syncRequest,
          batchSize: 50,
          fetchPrevTxouts: true
        )
        addToLog("Sync update received from server")
        syncState = .syncing("Applying update…")
        try wallet.applyUpdate(update: update)
        addToLog("Sync update applied to wallet")
        lastSyncType = .incremental
      }

      syncState = .syncing("Saving…")
      if let persister {
        addToLog("Persisting wallet state")
        _ = try wallet.persist(persister: persister)
      }

      // Update chain tip height for confirmation count calculation
      addToLog("Fetching chain tip height")
      if let header = try? client.blockHeadersSubscribe() {
        chainTipHeight = UInt32(header.height)
        addToLog("Chain tip height: \(chainTipHeight)")
      }

      updateCachedData()
      pruneStaleeSavedPSBTs()

      let now = Date()
      lastSyncDate = now
      syncState = .synced(now)
      addToLog("Sync completed successfully")
    } catch {
      let errorMsg = "\(error)"
      addToLog("Sync failed with error: \(errorMsg)")
      syncState = .error(errorMsg)
      throw error
    }
  }

  func fullResync() async throws {
    needsFullScan = true
    try await sync()
  }

  func testElectrumConnection(config: ElectrumConfig) async throws {
    let client = try ElectrumClient(url: config.url)
    try client.ping()
  }

  // MARK: - Data Queries

  private func updateCachedData() {
    guard let wallet else { return }

    let bal = wallet.balance()
    balance = bal.total.toSat()

    let network = bdkNetwork(from: currentProfile?.bitcoinNetwork ?? .testnet4)

    let txList = wallet.transactions()
    transactions = txList.map { canonicalTx -> TransactionItem in
      let tx = canonicalTx.transaction
      let txid = tx.computeTxid().description

      let sentAndReceived = wallet.sentAndReceived(tx: tx)
      let sent = sentAndReceived.sent.toSat()
      let received = sentAndReceived.received.toSat()

      let isIncoming = received > sent
      let amount: Int64 = isIncoming ? Int64(received - sent) : -Int64(sent - received)

      var confirmations: UInt32 = 0
      var timestamp: Date?
      var blockHeight: UInt32?
      var firstSeen: Date?

      switch canonicalTx.chainPosition {
      case let .confirmed(confirmationBlockTime, _):
        blockHeight = confirmationBlockTime.blockId.height
        if chainTipHeight > 0, let bh = blockHeight {
          confirmations = chainTipHeight >= bh ? chainTipHeight - bh + 1 : 1
        } else {
          confirmations = 1
        }
        if confirmationBlockTime.confirmationTime > 0 {
          timestamp = Date(timeIntervalSince1970: TimeInterval(confirmationBlockTime.confirmationTime))
        }
        // Cleanup firstSeen if tx is now confirmed
        let defaultKey = "firstSeen_\(txid)"
        if UserDefaults.standard.object(forKey: defaultKey) != nil {
          UserDefaults.standard.removeObject(forKey: defaultKey)
        }
      case let .unconfirmed(lastSeen):
        confirmations = 0
        timestamp = nil
        if let lastSeen, lastSeen > 0 {
          let defaultKey = "firstSeen_\(txid)"
          let stored = UserDefaults.standard.double(forKey: defaultKey)
          if stored > 0 {
            firstSeen = Date(timeIntervalSince1970: stored)
          } else {
            firstSeen = Date(timeIntervalSince1970: TimeInterval(lastSeen))
            UserDefaults.standard.set(TimeInterval(lastSeen), forKey: defaultKey)
          }
        }
      }

      let feeAmount: UInt64? = (try? wallet.calculateFee(tx: tx).toSat())
      let txVsize = tx.vsize()

      // Extract outputs
      let outputs: [TransactionItem.TxIO] = tx.output().map { txOut in
        let address = (try? Address.fromScript(script: txOut.scriptPubkey, network: network).description) ?? "Unknown"
        let mine = wallet.isMine(script: txOut.scriptPubkey)
        return TransactionItem.TxIO(
          address: address,
          amount: txOut.value.toSat(),
          prevTxid: nil,
          prevVout: nil,
          isMine: mine
        )
      }

      // Extract inputs (resolve address and amount from previous output when possible)
      let inputs: [TransactionItem.TxIO] = tx.input().map { txIn in
        let prevTxid = txIn.previousOutput.txid.description
        let prevVout = txIn.previousOutput.vout
        var inputAmount: UInt64 = 0
        var mine = false
        var address = prevTxid.truncatedMiddle() + ":\(prevVout)"
        if let prevTx = txList.first(where: { $0.transaction.computeTxid().description == prevTxid }) {
          let prevOutputs = prevTx.transaction.output()
          if prevVout < prevOutputs.count {
            let prevOut = prevOutputs[Int(prevVout)]
            inputAmount = prevOut.value.toSat()
            mine = wallet.isMine(script: prevOut.scriptPubkey)
            if let addr = try? Address.fromScript(script: prevOut.scriptPubkey, network: network).description {
              address = addr
            }
          }
        }
        return TransactionItem.TxIO(
          address: address,
          amount: inputAmount,
          prevTxid: prevTxid,
          prevVout: prevVout,
          isMine: mine
        )
      }

      return TransactionItem(
        id: txid,
        amount: amount,
        fee: feeAmount,
        confirmations: confirmations,
        timestamp: timestamp,
        isIncoming: isIncoming,
        blockHeight: blockHeight,
        vsize: txVsize,
        firstSeen: firstSeen,
        inputs: inputs,
        outputs: outputs
      )
    }.sorted {
      let isUnconfirmed0 = $0.confirmations == 0
      let isUnconfirmed1 = $1.confirmations == 0
      if isUnconfirmed0 != isUnconfirmed1 {
        return isUnconfirmed0
      }
      return ($0.timestamp ?? $0.firstSeen ?? .distantPast) > ($1.timestamp ?? $1.firstSeen ?? .distantPast)
    }

    let unspent = wallet.listUnspent()
    utxos = unspent.map { output in
      let confirmed = switch output.chainPosition {
      case .confirmed: true
      case .unconfirmed: false
      }
      return UTXOItem(
        txid: output.outpoint.txid.description,
        vout: output.outpoint.vout,
        amount: output.txout.value.toSat(),
        isConfirmed: confirmed,
        keychain: output.keychain == .external ? .external : .internal
      )
    }.sorted { u0, u1 in
      let isUnconfirmed0 = !u0.isConfirmed
      let isUnconfirmed1 = !u1.isConfirmed
      if isUnconfirmed0 != isUnconfirmed1 {
        return isUnconfirmed0
      }
      let tx0 = transactions.first(where: { $0.id == u0.txid })
      let tx1 = transactions.first(where: { $0.id == u1.txid })
      return (tx0?.timestamp ?? tx0?.firstSeen ?? .distantPast) > (tx1?.timestamp ?? tx1?.firstSeen ?? .distantPast)
    }
  }

  // MARK: - Saved PSBT Pruning

  /// Remove saved PSBTs whose inputs have been spent (no longer in the UTXO set).
  private func pruneStaleeSavedPSBTs() {
    guard let walletID = currentProfile?.id,
          let container = modelContainer else { return }

    let currentOutpoints = Set(utxos.map(\.id)) // "txid:vout"

    do {
      let context = ModelContext(container)
      let descriptor = FetchDescriptor<SavedPSBT>(predicate: #Predicate { $0.walletID == walletID })
      let savedPSBTs = try context.fetch(descriptor)

      for saved in savedPSBTs {
        let inputOutpoints = saved.inputOutpoints
          .split(separator: ",")
          .map(String.init)
          .filter { !$0.isEmpty }

        // If we have no stored outpoints, skip (legacy saved PSBTs before this field existed)
        guard !inputOutpoints.isEmpty else { continue }

        // If any input is no longer in the UTXO set, the PSBT is stale
        let hasSpentInput = inputOutpoints.contains { !currentOutpoints.contains($0) }
        if hasSpentInput {
          addToLog("Pruning stale saved PSBT '\(saved.name)': input spent")
          context.delete(saved)
        }
      }

      try context.save()
    } catch {
      addToLog("Failed to prune saved PSBTs: \(error)")
    }
  }

  // MARK: - Addresses

  func getNextAddress() throws -> (String, UInt32) {
    guard let wallet else { throw AppError.walletNotLoaded }
    let usedAddresses = buildUsedAddressSet()
    for i in 0 ..< UInt32(Constants.maxAddressGap) {
      let info = wallet.peekAddress(keychain: .external, index: i)
      if !usedAddresses.contains(info.address.description) {
        return (info.address.description, info.index)
      }
    }
    // All peeked addresses are used — reveal a new one
    let info = wallet.revealNextAddress(keychain: .external)
    if let persister {
      _ = try wallet.persist(persister: persister)
    }
    return (info.address.description, info.index)
  }

  func revealNextAddress() throws -> (String, UInt32) {
    guard let wallet else { throw AppError.walletNotLoaded }
    let info = wallet.revealNextAddress(keychain: .external)
    if let persister {
      _ = try wallet.persist(persister: persister)
    }
    return (info.address.description, info.index)
  }

  func getAddresses(keychain: UTXOItem.KeychainKind) -> [AddressItem] {
    guard let wallet else { return [] }
    let bdkKeychain: KeychainKind = keychain == .external ? .external : .internal
    let usedAddresses = buildUsedAddressSet()
    let gapLimit = currentProfile?.addressGapLimit ?? Constants.maxAddressGap

    // Scan addresses, always ensuring gapLimit unused addresses after the last used one.
    // We extend the scan window each time we find a used address.
    var items: [AddressItem] = []
    var lastUsedIndex: Int = -1
    var i: UInt32 = 0

    while Int(i) <= lastUsedIndex + gapLimit {
      let info = wallet.peekAddress(keychain: bdkKeychain, index: i)
      let addr = info.address.description
      let isUsed = usedAddresses.contains(addr)
      if isUsed {
        lastUsedIndex = Int(i)
      }
      items.append(AddressItem(
        index: i,
        address: addr,
        isUsed: isUsed,
        isChange: keychain == .internal
      ))
      i += 1
    }

    return items
  }

  private func buildUsedAddressSet() -> Set<String> {
    guard let wallet else { return [] }
    let network = bdkNetwork(from: currentProfile?.bitcoinNetwork ?? .testnet4)
    var addresses = Set<String>()
    for canonicalTx in wallet.transactions() {
      for output in canonicalTx.transaction.output() {
        if let addr = try? Address.fromScript(script: output.scriptPubkey, network: network).description {
          addresses.insert(addr)
        }
      }
    }
    return addresses
  }

  // MARK: - Fee Estimation

  struct RecommendedFees {
    let high: Float // Target: ~1 block
    let medium: Float // Target: ~6 blocks
    let low: Float // Target: ~144 blocks
    let defaultRate: Float // Fallback

    var fastest: Float {
      max(high, 1.0)
    }

    var hour: Float {
      max(medium, 1.0)
    }

    var economy: Float {
      max(low, 1.0)
    }
  }

  /// Fetches estimated fee rates in sats/vB from the connected Electrum server
  func getFeeRates() async throws -> RecommendedFees {
    guard let electrumClient else {
      throw AppError.electrumConnectionFailed("Not connected to server")
    }

    // Electrum returns BTC/kB. To convert to sats/vB:
    // BTC -> sats = * 100,000,000
    // kB -> vB = / 1000
    // So multiplier is 100,000
    let multiplier: Double = 100_000

    // Fetch using Task to push it to a background thread as BDK methods are synchronous
    return await Task.detached {
      let highRaw = try? electrumClient.estimateFee(number: 1)
      let medRaw = try? electrumClient.estimateFee(number: 6)
      let lowRaw = try? electrumClient.estimateFee(number: 144)

      // Calculate sats/vB. If server returns negative or invalid, fallback to 1.0
      var highRate = Float((highRaw ?? -1) * multiplier)
      var medRate = Float((medRaw ?? -1) * multiplier)
      var lowRate = Float((lowRaw ?? -1) * multiplier)

      // Sanity cap: Testnet electrum servers sometimes return absurdly high values (e.g., 3000+ sats/vB).
      // Cap the suggested rates to realistic maximums to prevent user shock.
      let maxSaneRate: Float = 500.0
      if highRate > maxSaneRate { highRate = 5.0 }
      if medRate > maxSaneRate { medRate = 2.0 }
      if lowRate > maxSaneRate { lowRate = 1.0 }

      return RecommendedFees(
        high: highRate > 0 ? highRate : 5.0,
        medium: medRate > 0 ? medRate : 2.0,
        low: lowRate > 0 ? lowRate : 1.0,
        defaultRate: 2.0
      )
    }.value
  }

  // MARK: - PSBT

  struct PSBTResult {
    let base64: String
    let bytes: Data
    let fee: UInt64
    let changeAmount: UInt64?
    let changeAddress: String?
    let inputCount: Int
  }

  func createPSBT(
    recipients: [(address: String, amount: UInt64, isSendMax: Bool)],
    feeRate: UInt64,
    utxos: [(txid: String, vout: UInt32)]? = nil
  ) async throws -> PSBTResult {
    guard let wallet else { throw AppError.walletNotLoaded }

    let network = bdkNetwork(from: currentProfile?.bitcoinNetwork ?? .testnet4)
    let bdkFeeRate = try FeeRate.fromSatPerVb(satVb: max(feeRate, 1))

    let safeHeight = chainTipHeight > 0 ? chainTipHeight - 1 : 0
    var builder = TxBuilder()
      .feeRate(feeRate: bdkFeeRate)
      .addGlobalXpubs()
      .nlocktime(locktime: .blocks(height: safeHeight))

    // Manual UTXO selection
    if let utxos, !utxos.isEmpty {
      let outpoints = try utxos.map { try OutPoint(txid: Txid.fromString(hex: $0.txid), vout: $0.vout) }
      builder = builder.addUtxos(outpoints: outpoints).manuallySelectedOnly()
    }

    let recipientScripts = try Set(recipients.map { r in
      try Address(address: r.address, network: network).scriptPubkey().toBytes()
    })

    for recipient in recipients {
      let address = try Address(address: recipient.address, network: network)
      let script = address.scriptPubkey()

      if recipient.isSendMax {
        builder = builder.drainTo(script: script).drainWallet()
      } else {
        builder = builder.addRecipient(script: script, amount: Amount.fromSat(satoshi: recipient.amount))
      }
    }

    let psbt = try builder.finish(wallet: wallet)
    let fee = try psbt.fee()

    let inputCount = psbt.input().count

    // Identify change output via PSBT output metadata: if an output has bip32Derivation
    // data but is NOT a recipient script, it's the change output. This avoids extractTx()
    // which can fail on unsigned PSBTs.
    var changeAmount: UInt64?
    var changeAddress: String?
    if let tx = try? psbt.extractTx() {
      let txOutputs = tx.output()
      let psbtOutputs = psbt.output()
      for (i, psbtOut) in psbtOutputs.enumerated() where i < txOutputs.count {
        let scriptBytes = txOutputs[i].scriptPubkey.toBytes()
        if !psbtOut.bip32Derivation.isEmpty, !recipientScripts.contains(scriptBytes) {
          changeAmount = txOutputs[i].value.toSat()
          changeAddress = (try? Address.fromScript(script: txOutputs[i].scriptPubkey, network: network))?.description
        }
      }
    }

    let base64 = psbt.serialize()
    guard let bytes = Data(base64Encoded: base64) else {
      throw AppError.psbtFinalizeFailed("Failed to decode PSBT base64")
    }
    return PSBTResult(base64: base64, bytes: bytes, fee: fee, changeAmount: changeAmount, changeAddress: changeAddress, inputCount: inputCount)
  }

  func createBumpFeePSBT(txid: String, feeRate: UInt64) async throws -> PSBTResult {
    guard let wallet else { throw AppError.walletNotLoaded }

    let network = bdkNetwork(from: currentProfile?.bitcoinNetwork ?? .testnet4)
    let bdkFeeRate = try FeeRate.fromSatPerVb(satVb: max(feeRate, 1))

    let safeHeight = chainTipHeight > 0 ? chainTipHeight - 1 : 0
    let bdkTxid = try Txid.fromString(hex: txid)
    let psbt = try BumpFeeTxBuilder(txid: bdkTxid, feeRate: bdkFeeRate)
      .nlocktime(locktime: .blocks(height: safeHeight))
      .finish(wallet: wallet)
    let fee = try psbt.fee()

    let inputCount = psbt.input().count

    // Identify change output via PSBT output bip32Derivation (wallet-owned outputs)
    var changeAmount: UInt64?
    var changeAddress: String?
    if let tx = try? psbt.extractTx() {
      let txOutputs = tx.output()
      let psbtOutputs = psbt.output()
      for (i, psbtOut) in psbtOutputs.enumerated() where i < txOutputs.count {
        if !psbtOut.bip32Derivation.isEmpty {
          changeAmount = txOutputs[i].value.toSat()
          changeAddress = (try? Address.fromScript(script: txOutputs[i].scriptPubkey, network: network))?.description
        }
      }
    }

    let base64 = psbt.serialize()
    guard let bytes = Data(base64Encoded: base64) else {
      throw AppError.psbtFinalizeFailed("Failed to decode PSBT base64")
    }
    return PSBTResult(base64: base64, bytes: bytes, fee: fee, changeAmount: changeAmount, changeAddress: changeAddress, inputCount: inputCount)
  }

  func combinePSBTs(original: Data, signed: Data) async throws -> (String, Data) {
    let originalBase64 = original.base64EncodedString()
    let signedBase64 = signed.base64EncodedString()

    let psbt = try Psbt(psbtBase64: originalBase64)
    let signedPsbt = try Psbt(psbtBase64: signedBase64)

    // BDK's combine() enforces that the unsigned transaction matches at the BIP-174
    // level — structurally incompatible PSBTs are rejected. No additional validation needed.
    let combined = try psbt.combine(other: signedPsbt)

    let base64 = combined.serialize()
    guard let bytes = Data(base64Encoded: base64) else {
      throw AppError.psbtCombineFailed("Failed to decode combined PSBT base64")
    }
    return (base64, bytes)
  }

  func finalizePSBT(_ psbtData: Data) throws -> (psbt: Psbt, tx: Transaction) {
    guard let wallet else { throw AppError.walletNotLoaded }

    let base64 = psbtData.base64EncodedString()
    let psbt = try Psbt(psbtBase64: base64)

    // Use wallet.finalizePsbt which has full wallet context for finalizing
    // scripts (e.g. policy-based spending conditions). Falls back to psbt.finalize()
    // if the wallet method fails.
    let finalized: Bool
    do {
      finalized = try wallet.finalizePsbt(psbt: psbt)
    } catch {
      // wallet.finalizePsbt may throw SignerError; fall back to standalone finalize
      let result = psbt.finalize()
      guard result.couldFinalize else {
        let errorDetails = result.errors?.map { "\($0)" }.joined(separator: ", ") ?? "Unknown finalization error"
        throw AppError.psbtFinalizeFailed(errorDetails)
      }
      let tx = try result.psbt.extractTx()
      return (result.psbt, tx)
    }

    guard finalized else {
      throw AppError.psbtFinalizeFailed("Wallet could not finalize PSBT")
    }

    let tx = try psbt.extractTx()
    return (psbt, tx)
  }

  func psbtInputOutpoints(_ psbtData: Data) -> [String] {
    let base64 = psbtData.base64EncodedString()
    guard let psbt = try? Psbt(psbtBase64: base64),
          let tx = try? psbt.extractTx() else { return [] }
    return tx.input().map { "\($0.previousOutput.txid):\($0.previousOutput.vout)" }
  }

  func broadcastPSBT(_ psbtData: Data) async throws -> String {
    guard let client = electrumClient else {
      throw AppError.electrumConnectionFailed("Not connected to server")
    }

    let (_, tx) = try finalizePSBT(psbtData)
    return try client.transactionBroadcast(tx: tx).description
  }

  // MARK: - PSBT Import Validation

  struct PSBTImportResult {
    let psbtBytes: Data
    let psbtBase64: String
    let fee: UInt64
    let changeAmount: UInt64?
    let changeAddress: String?
    let inputCount: Int
    let recipients: [SavedRecipient]
    let feeRateSatVb: String
  }

  enum PSBTImportError: LocalizedError {
    case walletNotLoaded
    case invalidPSBT
    case inputNotOwned(outpoint: String)
    case inputSpent(outpoint: String)
    case inputFrozen(outpoint: String)

    var errorDescription: String? {
      switch self {
      case .walletNotLoaded: "Wallet not loaded"
      case .invalidPSBT: "Invalid PSBT data"
      case let .inputNotOwned(op): "Input \(op) is not owned by this wallet"
      case let .inputSpent(op): "Input \(op) has already been spent"
      case let .inputFrozen(op): "Input \(op) is frozen"
      }
    }
  }

  func validateAndParseImportedPSBT(_ psbtData: Data, frozenOutpoints: Set<String>) throws -> PSBTImportResult {
    guard let wallet else { throw PSBTImportError.walletNotLoaded }
    let network = bdkNetwork(from: currentProfile?.bitcoinNetwork ?? .testnet4)

    // Try parsing as base64 first, then as raw binary
    let psbt: Psbt
    if let base64String = String(data: psbtData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
       let parsed = try? Psbt(psbtBase64: base64String)
    {
      psbt = parsed
    } else if let parsed = try? Psbt(psbtBase64: psbtData.base64EncodedString()) {
      psbt = parsed
    } else {
      throw PSBTImportError.invalidPSBT
    }

    // Validate inputs
    let currentOutpoints = Set(utxos.map(\.id)) // "txid:vout"
    let psbtInputs = psbt.input()

    guard let tx = try? psbt.extractTx() else {
      throw PSBTImportError.invalidPSBT
    }

    let txInputs = tx.input()

    // 1. Check all inputs are owned by this wallet (via witness_utxo in PSBT inputs)
    for (i, input) in psbtInputs.enumerated() {
      if let witnessUtxo = input.witnessUtxo {
        guard wallet.isMine(script: witnessUtxo.scriptPubkey) else {
          let outpoint = i < txInputs.count
            ? "\(txInputs[i].previousOutput.txid):\(txInputs[i].previousOutput.vout)"
            : "unknown"
          throw PSBTImportError.inputNotOwned(outpoint: outpoint)
        }
      }
    }

    // 2. Check inputs are in UTXO set (not spent) and not frozen
    for txIn in txInputs {
      let outpoint = "\(txIn.previousOutput.txid):\(txIn.previousOutput.vout)"

      guard currentOutpoints.contains(outpoint) else {
        throw PSBTImportError.inputSpent(outpoint: outpoint)
      }

      if frozenOutpoints.contains(outpoint) {
        throw PSBTImportError.inputFrozen(outpoint: outpoint)
      }
    }

    // Extract transaction details
    let fee = (try? psbt.fee()) ?? 0
    let inputCount = psbtInputs.count

    // Identify change vs recipient outputs
    let txOutputs = tx.output()
    let psbtOutputs = psbt.output()
    var changeAmount: UInt64?
    var changeAddress: String?
    var recipientList: [SavedRecipient] = []

    for (i, txOut) in txOutputs.enumerated() {
      let address = (try? Address.fromScript(script: txOut.scriptPubkey, network: network))?.description ?? "Unknown"
      let amount = txOut.value.toSat()

      // If PSBT output has bip32Derivation, it's likely a wallet-owned output (change)
      let isChange = i < psbtOutputs.count && !psbtOutputs[i].bip32Derivation.isEmpty && wallet.isMine(script: txOut.scriptPubkey)

      if isChange {
        changeAmount = amount
        changeAddress = address
      } else {
        recipientList.append(SavedRecipient(address: address, amountSats: "\(amount)", isSendMax: false, label: ""))
      }
    }

    // Estimate fee rate
    let vsize = tx.vsize()
    let feeRate = vsize > 0 ? max(fee / vsize, 1) : 1

    let base64 = psbt.serialize()
    guard let bytes = Data(base64Encoded: base64) else {
      throw PSBTImportError.invalidPSBT
    }

    return PSBTImportResult(
      psbtBytes: bytes,
      psbtBase64: base64,
      fee: fee,
      changeAmount: changeAmount,
      changeAddress: changeAddress,
      inputCount: inputCount,
      recipients: recipientList,
      feeRateSatVb: "\(feeRate)"
    )
  }

  // MARK: - PSBT Signer Info

  struct PSBTSignerInfo {
    let totalSignatures: Int
    let signerFingerprints: Set<String>
    let cosignerSignStatus: [(label: String, fingerprint: String, hasSigned: Bool)]
  }

  func psbtSignerInfo(_ psbtData: Data) -> PSBTSignerInfo? {
    guard let profile = currentProfile,
          let psbt = try? Psbt(psbtBase64: psbtData.base64EncodedString()) else { return nil }

    let inputs = psbt.input()
    guard !inputs.isEmpty else { return nil }

    // Collect unique pubkeys that have partial_sigs across any input
    var signerPubkeys: Set<String> = []
    for input in inputs {
      for pubkey in input.partialSigs.keys {
        signerPubkeys.insert(pubkey)
      }
    }

    // Build pubkey → master fingerprint mapping from bip32Derivation
    var pubkeyToFingerprint: [String: String] = [:]
    for input in inputs {
      for (pubkey, keySource) in input.bip32Derivation {
        pubkeyToFingerprint[pubkey] = keySource.fingerprint
      }
    }

    // Determine which master fingerprints have signed
    var signerFingerprints: Set<String> = []
    for pubkey in signerPubkeys {
      if let fp = pubkeyToFingerprint[pubkey] {
        signerFingerprints.insert(fp)
      }
    }

    // Match against wallet's cosigners
    let cosigners = profile.cosigners.sorted(by: { $0.orderIndex < $1.orderIndex })
    let cosignerStatus = cosigners.map { cosigner in
      (label: cosigner.label, fingerprint: cosigner.fingerprint,
       hasSigned: signerFingerprints.contains(cosigner.fingerprint))
    }

    return PSBTSignerInfo(
      totalSignatures: signerFingerprints.count,
      signerFingerprints: signerFingerprints,
      cosignerSignStatus: cosignerStatus
    )
  }

  // MARK: - Descriptor Building

  static func buildDescriptor(
    requiredSignatures: Int,
    cosigners: [(xpub: String, fingerprint: String, derivationPath: String)],
    network: BitcoinNetwork,
    isChange: Bool
  ) -> String {
    let chain = isChange ? "1" : "0"
    let coinType = network.coinType

    let sorted = cosigners.sorted { $0.xpub < $1.xpub }

    let keys = sorted.map { cosigner in
      let xpub = cosigner.xpub.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      return "[\(cosigner.fingerprint)/48'/\(coinType)'/0'/2']\(xpub)/\(chain)/*"
    }.joined(separator: ",")

    return "wsh(sortedmulti(\(requiredSignatures),\(keys)))"
  }

  /// Build a combined output descriptor with <0;1>/* multipath notation
  static func buildCombinedDescriptor(
    requiredSignatures: Int,
    cosigners: [(xpub: String, fingerprint: String, derivationPath: String)],
    network: BitcoinNetwork
  ) -> String {
    let coinType = network.coinType
    let sorted = cosigners.sorted { $0.xpub < $1.xpub }

    let keys = sorted.map { cosigner in
      let xpub = cosigner.xpub.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      return "[\(cosigner.fingerprint)/48'/\(coinType)'/0'/2']\(xpub)/<0;1>/*"
    }.joined(separator: ",")

    return "wsh(sortedmulti(\(requiredSignatures),\(keys)))"
  }

  // MARK: - Helpers

  private func bdkNetwork(from network: BitcoinNetwork) -> Network {
    switch network {
    case .mainnet: .bitcoin
    case .testnet4: .testnet4
    case .testnet3: .testnet
    case .signet: .signet
    }
  }
}

// MARK: - Sync Progress Inspectors

/// Reports per-script progress during full scan (keychain + derivation index)
final class FullScanProgressInspector: FullScanScriptInspector, @unchecked Sendable {
  private let onProgress: (KeychainKind, UInt32) -> Void

  init(onProgress: @escaping (KeychainKind, UInt32) -> Void) {
    self.onProgress = onProgress
  }

  func inspect(keychain: KeychainKind, index: UInt32, script _: Script) {
    DispatchQueue.main.async { [onProgress] in
      onProgress(keychain, index)
    }
  }
}

/// Reports per-script progress during incremental sync (script + total count)
final class SyncProgressInspector: SyncScriptInspector, @unchecked Sendable {
  private let onProgress: (Script, UInt64) -> Void

  init(onProgress: @escaping (Script, UInt64) -> Void) {
    self.onProgress = onProgress
  }

  func inspect(script: Script, total: UInt64) {
    DispatchQueue.main.async { [onProgress] in
      onProgress(script, total)
    }
  }
}
