import SwiftData
import SwiftUI

struct TransactionListView: View {
  @Query private var wallets: [WalletProfile]
  @Query private var walletLabels: [WalletLabel]
  @State private var viewModel = TransactionListViewModel()
  @State private var showConnectionStatus = false
  @State private var showDashboard = false
  @State private var showComingSoon = false
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
              Button(action: { showComingSoon = true }) {
                Label("Import Labels", systemImage: "square.and.arrow.down")
              }
              Button(action: { showComingSoon = true }) {
                Label("Export Labels", systemImage: "square.and.arrow.up")
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
      .alert("Feature Coming Soon", isPresented: $showComingSoon) {
        Button("OK", role: .cancel) {}
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
