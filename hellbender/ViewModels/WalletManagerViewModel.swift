import Foundation
import Observation
import SwiftData

@Observable
final class WalletManagerViewModel {
  var errorMessage: String?

  func setActiveWallet(_ wallet: WalletProfile, allWallets: [WalletProfile], modelContext: ModelContext) {
    for w in allWallets {
      w.isActive = (w.id == wallet.id)
    }
    UserDefaults.standard.set(wallet.id.uuidString, forKey: Constants.activeWalletIDKey)

    do {
      try modelContext.save()
      Task {
        try? await BitcoinService.shared.loadWallet(profile: wallet)
        try? await BitcoinService.shared.sync()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func deleteWallet(_ wallet: WalletProfile, modelContext: ModelContext) {
    let wasActive = wallet.isActive
    let walletID = wallet.id

    modelContext.delete(wallet)

    // Clean up wallet storage
    let walletDir = Constants.walletDirectory(for: walletID)
    try? FileManager.default.removeItem(at: walletDir)

    do {
      try modelContext.save()

      // If the active wallet was deleted, activate another one
      if wasActive {
        let remaining = (try? modelContext.fetch(FetchDescriptor<WalletProfile>())) ?? []
        if let next = remaining.first {
          next.isActive = true
          UserDefaults.standard.set(next.id.uuidString, forKey: Constants.activeWalletIDKey)
          try modelContext.save()
          Task {
            try? await BitcoinService.shared.loadWallet(profile: next)
          }
        } else {
          UserDefaults.standard.removeObject(forKey: Constants.activeWalletIDKey)
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
