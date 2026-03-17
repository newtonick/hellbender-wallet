import SwiftData
import SwiftUI

@main
struct hellbenderApp: App {
  let modelContainer: ModelContainer

  init() {
    do {
      let schema = Schema([WalletProfile.self, CosignerInfo.self, WalletLabel.self, FrozenUTXO.self, SavedPSBT.self])
      let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
      modelContainer = try ModelContainer(for: schema, configurations: [config])
      BitcoinService.shared.modelContainer = modelContainer
    } catch {
      fatalError("Failed to create ModelContainer: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .preferredColorScheme(.dark)
    }
    .modelContainer(modelContainer)
  }
}
