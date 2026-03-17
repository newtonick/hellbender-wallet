import Foundation
import Observation

@Observable
final class TransactionListViewModel {
  var transactions: [TransactionItem] = []
  var isLoading = false
  var balance: UInt64 = 0
  var walletName: String = ""
  var network: BitcoinNetwork = .testnet4
  var multisigDescription: String = ""

  private var bitcoinService: BitcoinService {
    BitcoinService.shared
  }

  var syncState: WalletSyncState {
    bitcoinService.syncState
  }

  func loadActiveWallet(from wallets: [WalletProfile]) {
    guard let active = wallets.first(where: { $0.isActive }) else { return }
    walletName = active.name
    network = active.bitcoinNetwork
    multisigDescription = active.multisigDescription

    let alreadyLoaded = bitcoinService.currentProfile?.id == active.id && bitcoinService.wallet != nil
    if alreadyLoaded {
      updateFromService()
    } else {
      Task {
        await loadWallet(active)
      }
    }
  }

  func loadWallet(_ profile: WalletProfile) async {
    do {
      try await bitcoinService.loadWallet(profile: profile)
      updateFromService()
      await refresh()
    } catch {
      // syncState is managed by BitcoinService
    }
  }

  func updateFromService() {
    balance = bitcoinService.balance
    transactions = bitcoinService.transactions
  }

  func refresh() async {
    isLoading = true
    do {
      try await bitcoinService.sync()
      updateFromService()
    } catch {
      // syncState is managed by BitcoinService
    }
    isLoading = false
  }
}
