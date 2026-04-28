import Foundation
@testable import birch
import Testing
import URKit

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

  // MARK: - Descriptor Checksum

  private static let realTestnetCosigners: [(xpub: String, fingerprint: String, derivationPath: String)] = [
    (xpub: "tpubDFH9dgzveyD8zTbPUFuLrGmCydNvxehyNdUXKJAQN8x4aZ4j6UZqGfnqFrD4NqyaTVGKbvEW54tsvPTK2UoSbCC1PJY8iCNiwTL3RWZEheQ",
     fingerprint: "73c5da0a", derivationPath: "m/48'/1'/0'/2'"),
    (xpub: "tpubDFcMWLJTavzfRa3Rc5i3bTMGBW7kYBLhLMJpLGSEik5pVhN5SMNKyVXHEB3Wnz6haXBMLF5MUiGMrawKaYFoZhBFNnEv7XEiv3FtGkBLtEHj",
     fingerprint: "f3ab64d8", derivationPath: "m/48'/1'/0'/2'"),
    (xpub: "tpubDEmRJGMra7j5TnqBb4F8d43geT8sNXkWBzJbAjWz5n3Bm4EJ4CjxqwT2BqNNyVmGdXmMsBafF4vaVhEsEwNeXCxRN1mvPuDJCxPPBkpcjwY",
     fingerprint: "c0b5ce41", derivationPath: "m/48'/1'/0'/2'"),
  ]

  @Test func combinedDescriptorHasChecksum() {
    let desc = BitcoinService.buildCombinedDescriptor(
      requiredSignatures: 2,
      cosigners: Self.realTestnetCosigners,
      network: .testnet4
    )

    // BIP-380 checksum is 8 characters after a '#'
    #expect(desc.contains("#"), "Combined descriptor should contain a checksum separator")
    let parts = desc.split(separator: "#")
    #expect(parts.count == 2, "Should have exactly one '#' separator")
    #expect(parts[1].count == 8, "Checksum should be 8 characters, got '\(parts[1])'")
  }

  @Test func combinedDescriptorChecksumIsDeterministic() {
    let desc1 = BitcoinService.buildCombinedDescriptor(
      requiredSignatures: 2,
      cosigners: Self.realTestnetCosigners,
      network: .testnet4
    )
    let desc2 = BitcoinService.buildCombinedDescriptor(
      requiredSignatures: 2,
      cosigners: Self.realTestnetCosigners,
      network: .testnet4
    )

    #expect(desc1 == desc2, "Same inputs should produce the same checksummed descriptor")
  }

  @Test func combinedDescriptorChecksumPreservesContent() {
    let desc = BitcoinService.buildCombinedDescriptor(
      requiredSignatures: 2,
      cosigners: Self.realTestnetCosigners,
      network: .testnet4
    )

    #expect(desc.hasPrefix("wsh(sortedmulti(2,"), "Should still start with wsh(sortedmulti(2,")
    #expect(desc.contains("<0;1>/*"), "Should still contain multipath notation")
    #expect(desc.contains("[73c5da0a/48'/1'/0'/2']"), "Should contain cosigner fingerprint/path")
  }

  /// Real descriptor decoded from a known-good crypto-output UR (from URServiceTests)
  private func realURDescriptor() -> String? {
    let urString = "UR:CRYPTO-OUTPUT/TAADMETAADMSOEADADAOLFTAADDLOSAOWKAXHDCLAOPDFNLNESAXHSJOFTVWFWHPTDUYPYHSROVLSWVDSRVWKBNNECZTHYMOURGSFDVDVAAAHDCXGMDKHPWMZTLRSOBSMWIOBWFWRPTODKNSEYAMTAHKRKQDISJTGWNSTSSFQDKPZSVTAHTAADEHOEADAEAOADAMTAADDYOTADLOCSDYYKADYKAEYKAOYKAOCYDYOTJEGMAXAAAYCYOYJNLKZMASJZGUIHIHIEGUINIOJTIHJPCXEYTAADDLOSAOWKAXHDCLAXIYMYFYWEMKASIOVSFYFDFDVASWONMTSKURSSTDMHVWSKLEAMKOVSGSDSCNSGNDOEAAHDCXBAMHFTFLGSDTBGBGFGGUREENGLFYTSHSCEJNKPHGGLFDFMTEWLENBDBBOXDYEMWTAHTAADEHOEADAEAOADAMTAADDYOTADLOCSDYYKADYKAEYKAOYKAOCYKNBWOSPAAXAAAYCYGRFPNSJOASJZGUIHIHIEGUINIOJTIHJPCXEHDLSWWZMD"
    let result = URService.processURString(urString)
    guard case let .descriptor(desc) = result else { return nil }
    return desc
  }

  @Test func checksumDoesNotAffectUREncoding() throws {
    guard let desc = realURDescriptor() else {
      Issue.record("Failed to decode test UR to descriptor")
      return
    }

    let checksum = BitcoinService.descriptorChecksum(desc)
    #expect(checksum.count == 8, "Checksum should be 8 characters")

    let descWithChecksum = desc + "#" + checksum

    // Encode both with and without checksum
    let urWithChecksum = try URService.encodeCryptoOutput(descriptor: descWithChecksum)
    let urWithoutChecksum = try URService.encodeCryptoOutput(descriptor: desc)

    // The CBOR data should be identical — checksum is stripped before encoding
    #expect(
      urWithChecksum.cbor.cborData == urWithoutChecksum.cbor.cborData,
      "Checksum should not affect the UR CBOR encoding"
    )
  }

  @Test func checksumDoesNotAffectAnimatedQRFrames() throws {
    guard let desc = realURDescriptor() else {
      Issue.record("Failed to decode test UR to descriptor")
      return
    }

    let checksum = BitcoinService.descriptorChecksum(desc)
    let descWithChecksum = desc + "#" + checksum

    let urWithChecksum = try URService.encodeCryptoOutput(descriptor: descWithChecksum)
    let urWithoutChecksum = try URService.encodeCryptoOutput(descriptor: desc)

    let maxFragmentLen = 160

    let encoderWith = UREncoder(urWithChecksum, maxFragmentLen: maxFragmentLen)
    let encoderWithout = UREncoder(urWithoutChecksum, maxFragmentLen: maxFragmentLen)

    // Same number of parts
    #expect(
      encoderWith.seqLen == encoderWithout.seqLen,
      "Both should produce the same number of UR parts"
    )

    // Same part content
    for i in 0 ..< encoderWith.seqLen {
      let partWith = encoderWith.nextPart()
      let partWithout = encoderWithout.nextPart()
      #expect(
        partWith == partWithout,
        "UR part \(i) should be identical regardless of checksum"
      )
    }
  }
}
