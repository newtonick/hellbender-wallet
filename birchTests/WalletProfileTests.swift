import Foundation
@testable import birch
import SwiftData
import Testing

struct WalletProfileTests {
  private func createTestContainer() throws -> ModelContainer {
    let schema = Schema([WalletProfile.self, CosignerInfo.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
  }

  @Test func createAndPersistProfile() throws {
    let container = try createTestContainer()
    let context = ModelContext(container)

    let profile = WalletProfile(
      name: "Test Wallet",
      requiredSignatures: 2,
      totalCosigners: 3,
      externalDescriptor: "wsh(sortedmulti(2,...))",
      internalDescriptor: "wsh(sortedmulti(2,...))",
      network: .testnet4,
      isActive: true
    )

    context.insert(profile)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<WalletProfile>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.name == "Test Wallet")
    #expect(fetched.first?.requiredSignatures == 2)
    #expect(fetched.first?.totalCosigners == 3)
    #expect(fetched.first?.isActive == true)
    #expect(fetched.first?.bitcoinNetwork == .testnet4)
  }

  @Test func onlyOneActiveWallet() throws {
    let container = try createTestContainer()
    let context = ModelContext(container)

    let wallet1 = WalletProfile(
      name: "Wallet 1", requiredSignatures: 2, totalCosigners: 3,
      externalDescriptor: "wsh(...)", internalDescriptor: "wsh(...)",
      network: .testnet4, isActive: true
    )
    let wallet2 = WalletProfile(
      name: "Wallet 2", requiredSignatures: 2, totalCosigners: 2,
      externalDescriptor: "wsh(...)", internalDescriptor: "wsh(...)",
      network: .testnet4, isActive: false
    )

    context.insert(wallet1)
    context.insert(wallet2)
    try context.save()

    // Activate wallet 2, deactivate wallet 1
    wallet1.isActive = false
    wallet2.isActive = true
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<WalletProfile>())
    let active = fetched.filter(\.isActive)
    #expect(active.count == 1)
    #expect(active.first?.name == "Wallet 2")
  }

  @Test func cascadeDeleteCosigners() throws {
    let container = try createTestContainer()
    let context = ModelContext(container)

    let wallet = WalletProfile(
      name: "Test", requiredSignatures: 2, totalCosigners: 2,
      externalDescriptor: "wsh(...)", internalDescriptor: "wsh(...)",
      network: .testnet4, isActive: true
    )
    context.insert(wallet)

    let cosigner1 = CosignerInfo(
      label: "Cosigner 1", xpub: "tpubA", fingerprint: "aaaaaaaa",
      derivationPath: "m/48'/1'/0'/2'", orderIndex: 0
    )
    cosigner1.wallet = wallet
    context.insert(cosigner1)

    let cosigner2 = CosignerInfo(
      label: "Cosigner 2", xpub: "tpubB", fingerprint: "bbbbbbbb",
      derivationPath: "m/48'/1'/0'/2'", orderIndex: 1
    )
    cosigner2.wallet = wallet
    context.insert(cosigner2)

    try context.save()

    // Verify cosigners exist
    let cosigners = try context.fetch(FetchDescriptor<CosignerInfo>())
    #expect(cosigners.count == 2)

    // Delete wallet
    context.delete(wallet)
    try context.save()

    // Cosigners should be cascade deleted
    let remaining = try context.fetch(FetchDescriptor<CosignerInfo>())
    #expect(remaining.count == 0)
  }

  @Test func multisigDescription() {
    let wallet = WalletProfile(
      name: "Test", requiredSignatures: 2, totalCosigners: 3,
      externalDescriptor: "", internalDescriptor: "",
      network: .testnet4
    )
    #expect(wallet.multisigDescription == "2-of-3")
  }

  @Test func multipleWalletsSwitching() throws {
    let container = try createTestContainer()
    let context = ModelContext(container)

    for i in 1 ... 3 {
      let wallet = WalletProfile(
        name: "Wallet \(i)", requiredSignatures: 2, totalCosigners: 3,
        externalDescriptor: "wsh(...\(i))", internalDescriptor: "wsh(...\(i))",
        network: .testnet4, isActive: i == 1
      )
      context.insert(wallet)
    }
    try context.save()

    let wallets = try context.fetch(FetchDescriptor<WalletProfile>())
    #expect(wallets.count == 3)

    // Switch to wallet 3
    for w in wallets {
      w.isActive = (w.name == "Wallet 3")
    }
    try context.save()

    let active = wallets.filter(\.isActive)
    #expect(active.count == 1)
    #expect(active.first?.name == "Wallet 3")
  }
}
