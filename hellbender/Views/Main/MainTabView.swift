import SwiftData
import SwiftUI

struct MainTabView: View {
  @State private var selectedTab = 0
  @State private var walletID: UUID?
  @State private var resumePSBT: SavedPSBT?
  @State private var showResumeAlert = false
  @State private var pendingResumePSBT: SavedPSBT?
  @State private var resumeBumpFeeViewModel: BumpFeeViewModel?
  @State private var hasCheckedResume = false
  @Query(sort: \SavedPSBT.updatedAt, order: .reverse) private var allSavedPSBTs: [SavedPSBT]

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Transactions", systemImage: "list.bullet.rectangle", value: 0) {
        TransactionListView()
      }

      Tab("Send", systemImage: "arrow.up.right", value: 1) {
        SendFlowView(selectedTab: $selectedTab, resumePSBT: $resumePSBT)
      }

      Tab("Receive", systemImage: "arrow.down.left", value: 2) {
        ReceiveView()
      }

      Tab("UTXOs", systemImage: "bitcoinsign.circle", value: 3) {
        NavigationStack {
          UTXOListView()
        }
        .id(walletID)
      }

      Tab("Settings", systemImage: "gearshape.fill", value: 4) {
        SettingsView()
      }
    }
    .tint(Color.hbBitcoinOrange)
    .onAppear {
      walletID = BitcoinService.shared.currentProfile?.id
    }
    .onChange(of: BitcoinService.shared.currentProfile?.id) {
      walletID = BitcoinService.shared.currentProfile?.id
      checkForInProgressPSBT()
    }
    .onChange(of: allSavedPSBTs.count) {
      checkForInProgressPSBT()
    }
    .alert("Resume Signing?", isPresented: $showResumeAlert) {
      Button("Yes") {
        guard let saved = pendingResumePSBT else { return }
        pendingResumePSBT = nil
        if saved.originalTxid != nil {
          resumeBumpFeeViewModel = BumpFeeViewModel(savedPSBT: saved)
        } else {
          selectedTab = 1
          // Delay so the tab switch completes before SendFlowView loads the PSBT
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            resumePSBT = saved
          }
        }
      }
      Button("No", role: .cancel) {
        pendingResumePSBT = nil
      }
    } message: {
      Text("You have a PSBT that was being signed. Would you like to resume?")
    }
    .sheet(item: $resumeBumpFeeViewModel) { vm in
      BumpFeeView(viewModel: vm)
    }
  }

  private func checkForInProgressPSBT() {
    guard !hasCheckedResume else { return }
    guard let walletID = BitcoinService.shared.currentProfile?.id else { return }
    guard !allSavedPSBTs.isEmpty else { return }
    hasCheckedResume = true

    if let saved = allSavedPSBTs.first(where: { $0.walletID == walletID }) {
      pendingResumePSBT = saved
      showResumeAlert = true
    }
  }
}
