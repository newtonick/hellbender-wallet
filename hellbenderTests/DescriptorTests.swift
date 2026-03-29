import Foundation
@testable import hellbender
import Testing

@MainActor
struct DescriptorTests {
  // MARK: - Descriptor Construction

  @Test func buildTwoOfThreeDescriptor() {
    let cosigners: [(xpub: String, fingerprint: String, derivationPath: String)] = [
      (xpub: "tpubDFH9dgzveyD8zTbPUFuLrGmCydNvxehyNdUXKJAQN8x4aZ4j6UZqGfnqFrD4NqyaTVGKbvEW54tsvPTK2UoSbCC1PJY8iCNiwTL3RWZEheQ",
       fingerprint: "73c5da0a", derivationPath: "m/48'/1'/0'/2'"),
      (xpub: "tpubDFcMWLJTavzfRa3Rc5i3bTMGBW7kYBLhLMJpLGSEik5pVhN5SMNKyVXHEB3Wnz6haXBMLF5MUiGMrawKaYFoZhBFNnEv7XEiv3FtGkBLtEHj",
       fingerprint: "f3ab64d8", derivationPath: "m/48'/1'/0'/2'"),
      (xpub: "tpubDEmRJGMra7j5TnqBb4F8d43geT8sNXkWBzJbAjWz5n3Bm4EJ4CjxqwT2BqNNyVmGdXmMsBafF4vaVhEsEwNeXCxRN1mvPuDJCxPPBkpcjwY",
       fingerprint: "c0b5ce41", derivationPath: "m/48'/1'/0'/2'"),
    ]

    let external = BitcoinService.buildDescriptor(
      requiredSignatures: 2,
      cosigners: cosigners,
      network: .testnet4,
      isChange: false
    )

    #expect(external.hasPrefix("wsh(sortedmulti(2,"))
    #expect(external.hasSuffix("/0/*))"))
    #expect(external.contains("[73c5da0a/48'/1'/0'/2']"))
    #expect(external.contains("[f3ab64d8/48'/1'/0'/2']"))
    #expect(external.contains("[c0b5ce41/48'/1'/0'/2']"))
  }

  @Test func buildChangeDescriptor() {
    let cosigners: [(xpub: String, fingerprint: String, derivationPath: String)] = [
      (xpub: "tpubA", fingerprint: "aaaaaaaa", derivationPath: "m/48'/1'/0'/2'"),
      (xpub: "tpubB", fingerprint: "bbbbbbbb", derivationPath: "m/48'/1'/0'/2'"),
    ]

    let internal_desc = BitcoinService.buildDescriptor(
      requiredSignatures: 2,
      cosigners: cosigners,
      network: .testnet4,
      isChange: true
    )

    #expect(internal_desc.contains("/1/*"))
    #expect(!internal_desc.contains("/0/*"))
  }

  @Test func descriptorKeysAreSortedLexicographically() throws {
    let cosigners: [(xpub: String, fingerprint: String, derivationPath: String)] = [
      (xpub: "tpubZ", fingerprint: "11111111", derivationPath: "m/48'/1'/0'/2'"),
      (xpub: "tpubA", fingerprint: "22222222", derivationPath: "m/48'/1'/0'/2'"),
      (xpub: "tpubM", fingerprint: "33333333", derivationPath: "m/48'/1'/0'/2'"),
    ]

    let desc = BitcoinService.buildDescriptor(
      requiredSignatures: 2,
      cosigners: cosigners,
      network: .testnet4,
      isChange: false
    )

    // Keys should be sorted: tpubA, tpubM, tpubZ
    let aPos = try #require(desc.range(of: "tpubA")?.lowerBound)
    let mPos = try #require(desc.range(of: "tpubM")?.lowerBound)
    let zPos = try #require(desc.range(of: "tpubZ")?.lowerBound)

    #expect(aPos < mPos)
    #expect(mPos < zPos)
  }

  @Test func descriptorRoundTrip() {
    let cosigners: [(xpub: String, fingerprint: String, derivationPath: String)] = [
      (xpub: "tpubDFH9dgzveyD8zTbPUFuLrGmCydNvxehyNdUXKJAQN8x4aZ4j6UZqGfnqFrD4NqyaTVGKbvEW54tsvPTK2UoSbCC1PJY8iCNiwTL3RWZEheQ",
       fingerprint: "73c5da0a", derivationPath: "m/48'/1'/0'/2'"),
      (xpub: "tpubDFcMWLJTavzfRa3Rc5i3bTMGBW7kYBLhLMJpLGSEik5pVhN5SMNKyVXHEB3Wnz6haXBMLF5MUiGMrawKaYFoZhBFNnEv7XEiv3FtGkBLtEHj",
       fingerprint: "f3ab64d8", derivationPath: "m/48'/1'/0'/2'"),
    ]

    let desc1 = BitcoinService.buildDescriptor(
      requiredSignatures: 2,
      cosigners: cosigners,
      network: .testnet4,
      isChange: false
    )

    // Parse back via the wizard viewmodel
    let vm = SetupWizardViewModel()
    vm.importedDescriptorText = desc1
    let parsed = vm.parseImportedDescriptor()

    #expect(parsed)
    #expect(vm.requiredSignatures == 2)
    #expect(vm.totalCosigners == 2)

    // Rebuild from parsed data
    let reparsedCosigners = (0 ..< vm.totalCosigners).map { i in
      (xpub: vm.cosignerXpubs[i], fingerprint: vm.cosignerFingerprints[i], derivationPath: vm.cosignerDerivationPaths[i])
    }

    let desc2 = BitcoinService.buildDescriptor(
      requiredSignatures: vm.requiredSignatures,
      cosigners: reparsedCosigners,
      network: .testnet4,
      isChange: false
    )

    #expect(desc1 == desc2)
  }

  @Test func descriptorMainnetCoinType() {
    let cosigners: [(xpub: String, fingerprint: String, derivationPath: String)] = [
      (xpub: "xpubA", fingerprint: "aaaaaaaa", derivationPath: "m/48'/0'/0'/2'"),
      (xpub: "xpubB", fingerprint: "bbbbbbbb", derivationPath: "m/48'/0'/0'/2'"),
    ]

    let desc = BitcoinService.buildDescriptor(
      requiredSignatures: 2,
      cosigners: cosigners,
      network: .mainnet,
      isChange: false
    )

    #expect(desc.contains("48'/0'/0'/2'"))
  }

  @Test func descriptorTestnetCoinType() {
    let cosigners: [(xpub: String, fingerprint: String, derivationPath: String)] = [
      (xpub: "tpubA", fingerprint: "aaaaaaaa", derivationPath: "m/48'/1'/0'/2'"),
      (xpub: "tpubB", fingerprint: "bbbbbbbb", derivationPath: "m/48'/1'/0'/2'"),
    ]

    let desc = BitcoinService.buildDescriptor(
      requiredSignatures: 2,
      cosigners: cosigners,
      network: .testnet4,
      isChange: false
    )

    #expect(desc.contains("48'/1'/0'/2'"))
  }

  // MARK: - Descriptor Parsing Validation

  @Test func rejectNonWshDescriptor() {
    let vm = SetupWizardViewModel()
    vm.importedDescriptorText = "sh(sortedmulti(2,[aabb/48'/1'/0'/2']tpubA/0/*,[ccdd/48'/1'/0'/2']tpubB/0/*))"
    let result = vm.parseImportedDescriptor()
    #expect(!result)
    #expect(vm.errorMessage != nil)
  }

  @Test func rejectEmptyDescriptor() {
    let vm = SetupWizardViewModel()
    vm.importedDescriptorText = ""
    let result = vm.parseImportedDescriptor()
    #expect(!result)
  }
}
