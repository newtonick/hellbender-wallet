@testable import birch
import Foundation
import Testing

@MainActor
struct AddressDerivationTests {
  @Test func addressPrefixTestnet() {
    let network = BitcoinNetwork.testnet4
    #expect(network.addressPrefix == "tb1")
  }

  @Test func addressPrefixMainnet() {
    let network = BitcoinNetwork.mainnet
    #expect(network.addressPrefix == "bc1")
  }

  @Test func deterministic() {
    // Same descriptor should always produce the same address sequence
    // This test validates the BitcoinService.buildDescriptor produces
    // deterministic output
    let cosigners: [(xpub: String, fingerprint: String, derivationPath: String)] = [
      (xpub: "tpubA", fingerprint: "aaaaaaaa", derivationPath: "m/48'/1'/0'/2'"),
      (xpub: "tpubB", fingerprint: "bbbbbbbb", derivationPath: "m/48'/1'/0'/2'"),
    ]

    let desc1 = BitcoinService.buildDescriptor(
      requiredSignatures: 2, cosigners: cosigners, network: .testnet4, isChange: false
    )
    let desc2 = BitcoinService.buildDescriptor(
      requiredSignatures: 2, cosigners: cosigners, network: .testnet4, isChange: false
    )

    #expect(desc1 == desc2)
  }

  @Test func receiveVsChangeDescriptors() {
    let cosigners: [(xpub: String, fingerprint: String, derivationPath: String)] = [
      (xpub: "tpubA", fingerprint: "aaaaaaaa", derivationPath: "m/48'/1'/0'/2'"),
      (xpub: "tpubB", fingerprint: "bbbbbbbb", derivationPath: "m/48'/1'/0'/2'"),
    ]

    let receive = BitcoinService.buildDescriptor(
      requiredSignatures: 2, cosigners: cosigners, network: .testnet4, isChange: false
    )
    let change = BitcoinService.buildDescriptor(
      requiredSignatures: 2, cosigners: cosigners, network: .testnet4, isChange: true
    )

    #expect(receive != change)
    #expect(receive.contains("/0/*"))
    #expect(change.contains("/1/*"))
  }
}
