import SwiftUI

struct MainTabView: View {
  @State private var selectedTab = 0
  @State private var walletID: UUID?

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Transactions", systemImage: "list.bullet.rectangle", value: 0) {
        TransactionListView()
      }

      Tab("Send", systemImage: "arrow.up.right", value: 1) {
        SendFlowView(selectedTab: $selectedTab)
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
    }
  }
}
