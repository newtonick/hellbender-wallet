import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TransactionListView: View {
  @Query private var wallets: [WalletProfile]
  @Query private var walletLabels: [WalletLabel]
  @Query private var frozenUTXOs: [FrozenUTXO]
  @State private var viewModel = TransactionListViewModel()
  @State private var showConnectionStatus = false
  @State private var showDashboard = false
  @State private var showImportFilePicker = false
  @State private var showImportQRScanner = false
  @State private var showExportQR = false
  @State private var exportQRData: Data?
  @State private var importResult: String?
  @State private var showImportResult = false
  @State private var walletID: UUID?
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.modelContext) private var modelContext
  @AppStorage(Constants.denominationKey) private var denomination: String = "sats"
  @AppStorage(Constants.fiatEnabledKey) private var fiatEnabled = false
  @AppStorage(Constants.fiatPrimaryKey) private var fiatPrimary = false

  private var bitcoinService: BitcoinService {
    BitcoinService.shared
  }

  private var fiatService: FiatPriceService {
    FiatPriceService.shared
  }

  private func txLabel(for txid: String) -> String? {
    guard let walletID = BitcoinService.shared.currentProfile?.id else { return nil }
    return walletLabels.first(where: { $0.walletID == walletID && $0.type == "tx" && $0.ref == txid })?.label
  }

  private func exportLabelsToFile() {
    guard let profile = bitcoinService.currentProfile else { return }
    let walletID = profile.id
    let cosigners = profile.cosigners
    let frozenOutpoints = Set(frozenUTXOs.filter { $0.walletID == walletID }.map(\.outpoint))
    let receiveAddresses = bitcoinService.getAddresses(keychain: .external)
    let changeAddresses = bitcoinService.getAddresses(keychain: .internal)

    let data = LabelService.exportBIP329(
      walletID: walletID,
      context: modelContext,
      transactions: bitcoinService.transactions,
      utxos: bitcoinService.utxos,
      frozenOutpoints: frozenOutpoints,
      receiveAddresses: receiveAddresses,
      changeAddresses: changeAddresses,
      cosigners: cosigners,
      requiredSignatures: profile.requiredSignatures,
      network: profile.bitcoinNetwork
    )

    let sanitizedName = profile.name.replacingOccurrences(of: " ", with: "-")
    let fileName = "\(sanitizedName)-labels.jsonl"
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    try? data.write(to: tempURL)

    let activityVC = UIActivityViewController(
      activityItems: [tempURL],
      applicationActivities: nil
    )
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          var topVC = windowScene.windows.first?.rootViewController else { return }
    while let presented = topVC.presentedViewController {
      topVC = presented
    }
    if let popover = activityVC.popoverPresentationController {
      popover.sourceView = topVC.view
      popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: 0, width: 0, height: 0)
    }
    topVC.present(activityVC, animated: true)
  }

  private func importLabelsFromFile(result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      guard url.startAccessingSecurityScopedResource() else {
        importResult = "Unable to access the selected file."
        showImportResult = true
        return
      }
      defer { url.stopAccessingSecurityScopedResource() }

      guard let data = try? Data(contentsOf: url) else {
        importResult = "Unable to read the selected file."
        showImportResult = true
        return
      }

      guard let profile = bitcoinService.currentProfile else { return }

      let count = LabelService.importBIP329(
        data: data,
        walletID: profile.id,
        cosigners: profile.cosigners,
        context: modelContext
      )

      if count == 0 {
        importResult = "No new labels found to import."
      } else {
        importResult = "Successfully imported \(count) label\(count == 1 ? "" : "s")."
      }
      showImportResult = true

    case .failure:
      importResult = "Failed to select a file."
      showImportResult = true
    }
  }

  private func exportLabelsToQR() {
    exportQRData = nil
    showExportQR = true
  }

  private func buildExportData() -> Data {
    guard let profile = bitcoinService.currentProfile else { return Data() }
    let walletID = profile.id
    let frozenOutpoints = Set(frozenUTXOs.filter { $0.walletID == walletID }.map(\.outpoint))
    let receiveAddresses = bitcoinService.getAddresses(keychain: .external)
    let changeAddresses = bitcoinService.getAddresses(keychain: .internal)

    return LabelService.exportBIP329(
      walletID: walletID,
      context: modelContext,
      transactions: bitcoinService.transactions,
      utxos: bitcoinService.utxos,
      frozenOutpoints: frozenOutpoints,
      receiveAddresses: receiveAddresses,
      changeAddresses: changeAddresses,
      cosigners: profile.cosigners,
      requiredSignatures: profile.requiredSignatures,
      network: profile.bitcoinNetwork
    )
  }

  private func handleQRImportResult(_ result: AppURResult) {
    showImportQRScanner = false

    guard case let .rawBytes(data) = result else {
      importResult = "Unexpected QR code type. Expected UR-encoded labels."
      showImportResult = true
      return
    }

    guard let profile = bitcoinService.currentProfile else { return }

    let count = LabelService.importBIP329(
      data: data,
      walletID: profile.id,
      cosigners: profile.cosigners,
      context: modelContext
    )

    if count == 0 {
      importResult = "No new labels found to import."
    } else {
      importResult = "Successfully imported \(count) label\(count == 1 ? "" : "s")."
    }
    showImportResult = true
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Wallet status header
        VStack(spacing: 8) {
          HStack {
            Button(action: { showConnectionStatus = true }) {
              SyncStatusDot(state: viewModel.syncState)
            }

            Text(viewModel.walletName)
              .font(.hbHeadline)
              .foregroundStyle(Color.hbTextPrimary)

            NetworkBadge(network: viewModel.network)

            Spacer()

            Menu {
              Button(action: { showDashboard = true }) {
                Label("Dashboard", systemImage: "chart.bar.xaxis")
              }
              Menu {
                Button(action: { showImportFilePicker = true }) {
                  Label("Labels File Import", systemImage: "square.and.arrow.down")
                }
                Button(action: { exportLabelsToFile() }) {
                  Label("Labels File Export", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(action: { showImportQRScanner = true }) {
                  Label("Labels QR Import", systemImage: "qrcode.viewfinder")
                }
              } label: {
                Label("Wallet Labels", systemImage: "tag")
              }
            } label: {
              Image(systemName: "ellipsis.circle")
                .font(.system(size: 20))
                .foregroundStyle(Color.hbTextSecondary)
            }
          }

          HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
              if fiatEnabled, fiatPrimary, let fiatStr = fiatService.formattedSatsToFiat(viewModel.balance) {
                Text(fiatStr)
                  .font(.hbAmountLarge)
                  .foregroundStyle(Color.hbTextPrimary)
                Text(viewModel.balance.formattedSats)
                  .font(.hbBody(14))
                  .foregroundStyle(Color.hbTextSecondary)
              } else {
                Text(viewModel.balance.formattedSats)
                  .font(.hbAmountLarge)
                  .foregroundStyle(Color.hbTextPrimary)
                if fiatEnabled, let fiatStr = fiatService.formattedSatsToFiat(viewModel.balance) {
                  Text(fiatStr)
                    .font(.hbBody(14))
                    .foregroundStyle(Color.hbTextSecondary)
                }
              }
            }
            .onTapGesture(count: 2) {
              if fiatEnabled { fiatPrimary.toggle() }
            }

            Spacer()

            if fiatEnabled {
              Button(action: { fiatPrimary.toggle() }) {
                Image(systemName: "arrow.up.arrow.down")
                  .font(.system(size: 14, weight: .medium))
                  .foregroundStyle(Color.hbTextSecondary)
                  .padding(8)
                  .background(Color.hbSurfaceElevated)
                  .clipShape(Circle())
              }
            }
          }

          HStack {
            Text(viewModel.multisigDescription + " multisig")
              .font(.hbLabel())
              .foregroundStyle(Color.hbTextSecondary)

            Spacer()

            if let syncMsg = viewModel.syncState.syncMessage {
              Text(syncMsg)
                .font(.hbLabel(11))
                .foregroundStyle(Color.hbTextSecondary)
                .contentTransition(.numericText())
            } else if let lastSynced = viewModel.syncState.lastSynced {
              TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text("Last refreshed \(lastSynced.relativeString)")
                  .font(.hbLabel(11))
                  .foregroundStyle(Color.hbTextSecondary)
              }
            }
          }
        }
        .hbCard()
        .padding(16)

        transactionContent
      }
      .background(Color.hbBackground)
      .navigationTitle("")
      .refreshable {
        await viewModel.refresh()
      }
      .sheet(isPresented: $showConnectionStatus) {
        ConnectionStatusView()
      }
      .sheet(isPresented: $showDashboard) {
        WalletDashboardView()
      }
      .fileImporter(
        isPresented: $showImportFilePicker,
        allowedContentTypes: [UTType(filenameExtension: "jsonl") ?? .plainText],
        allowsMultipleSelection: false
      ) { result in
        importLabelsFromFile(result: result)
      }
      .alert("Import Labels", isPresented: $showImportResult) {
        Button("OK", role: .cancel) {}
      } message: {
        if let importResult {
          Text(importResult)
        }
      }
      .sheet(isPresented: $showImportQRScanner) {
        URScannerSheet { result in
          handleQRImportResult(result)
        }
      }
      .sheet(isPresented: $showExportQR) {
        NavigationStack {
          ZStack {
            Color.hbBackground.ignoresSafeArea()

            VStack(spacing: 16) {
              if let data = exportQRData {
                URDisplaySheet(data: data, urType: "bytes", maxFragmentLen: 400)
                  .padding(5)
                  .background(Color.white)
                  .shadow(color: Color.hbBitcoinOrange.opacity(0.2), radius: 20)
              } else {
                VStack(spacing: 12) {
                  ProgressView()
                    .tint(Color.hbBitcoinOrange)
                    .scaleEffect(1.5)
                  Text("Preparing labels...")
                    .font(.hbBody(14))
                    .foregroundStyle(Color.hbTextSecondary)
                }
              }

              Text("Scan to import wallet labels")
                .font(.hbBody(14))
                .foregroundStyle(Color.hbTextSecondary)
            }
            .padding(24)
          }
          .navigationTitle("Export Labels")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Done") { showExportQR = false }
            }
          }
        }
        .task {
          if exportQRData == nil {
            let data = buildExportData()
            exportQRData = data
          }
        }
      }
    }
    .id(walletID)
    .onAppear {
      walletID = BitcoinService.shared.currentProfile?.id
      viewModel.loadActiveWallet(from: wallets)
      bitcoinService.startAutoSync()
      bitcoinService.autoSyncIfNeeded()
      viewModel.updateFromService()
      if fiatEnabled {
        Task { await fiatService.fetchRatesIfNeeded() }
      }
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .active {
        bitcoinService.startAutoSync()
        bitcoinService.autoSyncIfNeeded()
        viewModel.updateFromService()
        if fiatEnabled {
          Task { await fiatService.fetchRatesIfNeeded() }
        }
      } else {
        bitcoinService.stopAutoSync()
      }
    }
    .onChange(of: bitcoinService.syncState) { _, newState in
      viewModel.updateFromService()
      if case .synced = newState, let walletID = bitcoinService.currentProfile?.id {
        LabelService.propagateAddressLabels(
          transactions: bitcoinService.transactions,
          utxos: bitcoinService.utxos,
          context: modelContext,
          walletID: walletID
        )
      }
    }
    .onChange(of: BitcoinService.shared.currentProfile?.id) {
      walletID = BitcoinService.shared.currentProfile?.id
      viewModel.loadActiveWallet(from: wallets)
    }
  }

  @ViewBuilder
  private var transactionContent: some View {
    if viewModel.transactions.isEmpty {
      ScrollView {
        ContentUnavailableView(
          "No Transactions",
          systemImage: "bitcoinsign.circle",
          description: Text("Time to acquire the world's best money")
        )
        .frame(maxHeight: .infinity)
        .padding(.top, 100)
      }
    } else {
      List(viewModel.transactions) { tx in
        NavigationLink(destination: TransactionDetailView(transaction: tx, network: viewModel.network)) {
          TransactionRowView(transaction: tx, label: txLabel(for: tx.id), showChevron: false, showFiat: fiatEnabled && fiatPrimary)
        }
        .listRowBackground(Color.hbSurface)
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
    }
  }
}
