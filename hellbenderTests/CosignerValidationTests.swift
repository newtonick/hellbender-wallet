import Foundation
@testable import hellbender
import Testing

struct CosignerValidationTests {
  @Test func validFingerprint() {
    let vm = SetupWizardViewModel()
    #expect(vm.validateFingerprint("73c5da0a") == nil)
    #expect(vm.validateFingerprint("AABBCCDD") == nil)
    #expect(vm.validateFingerprint("00000000") == nil)
  }

  @Test func fingerprintTooShort() {
    let vm = SetupWizardViewModel()
    let error = vm.validateFingerprint("73c5da")
    #expect(error != nil)
    #expect(error?.contains("8") == true)
  }

  @Test func fingerprintTooLong() {
    let vm = SetupWizardViewModel()
    let error = vm.validateFingerprint("73c5da0a1b")
    #expect(error != nil)
  }

  @Test func fingerprintNonHex() {
    let vm = SetupWizardViewModel()
    let error = vm.validateFingerprint("73c5dazz")
    #expect(error != nil)
    #expect(error?.contains("hex") == true)
  }

  @Test func emptyFingerprint() {
    let vm = SetupWizardViewModel()
    let error = vm.validateFingerprint("")
    #expect(error != nil)
  }

  @Test func validTestnetXpub() {
    let vm = SetupWizardViewModel()
    vm.network = .testnet4
    vm.cosignerXpubs = ["", ""]

    let error = vm.validateCosignerXpub(
      "tpubDFH9dgzveyD8zTbPUFuLrGmCydNvxehyNdUXKJAQN8x4aZ4j6UZqGfnqFrD4NqyaTVGKbvEW54tsvPTK2UoSbCC1PJY8iCNiwTL3RWZEheQ",
      at: 0
    )
    #expect(error == nil)
  }

  @Test func rejectMainnetXpubOnTestnet() {
    let vm = SetupWizardViewModel()
    vm.network = .testnet4
    vm.cosignerXpubs = ["", ""]

    let error = vm.validateCosignerXpub(
      "xpub6CUGRUonZSQ4TWtTMmzXdrXDtypWKiKrhko4egpiMZbpiaQL2jkwSB1icqYh2cfDfVxdx4df189oLKnC5fSwqPfgyP3hooxujYzAu3fDVmz",
      at: 0
    )
    #expect(error != nil)
    #expect(error?.contains("tpub") == true)
  }

  @Test func rejectDuplicateXpub() {
    let vm = SetupWizardViewModel()
    vm.network = .testnet4
    let xpub = "tpubDFH9dgzveyD8zTbPUFuLrGmCydNvxehyNdUXKJAQN8x4aZ4j6UZqGfnqFrD4NqyaTVGKbvEW54tsvPTK2UoSbCC1PJY8iCNiwTL3RWZEheQ"
    vm.cosignerXpubs = [xpub, ""]

    let error = vm.validateCosignerXpub(xpub, at: 1)
    #expect(error != nil)
    #expect(error?.contains("Duplicate") == true)
  }

  @Test func rejectEmptyXpub() {
    let vm = SetupWizardViewModel()
    vm.network = .testnet4
    vm.cosignerXpubs = ["", ""]

    let error = vm.validateCosignerXpub("", at: 0)
    #expect(error != nil)
  }

  @Test func cosignerInfoValidation() {
    let valid = CosignerInfo(
      label: "Test",
      xpub: "tpubDFH9dgzveyD8",
      fingerprint: "73c5da0a",
      derivationPath: "m/48'/1'/0'/2'",
      orderIndex: 0
    )
    #expect(valid.isValidFingerprint)

    let invalidFP = CosignerInfo(
      label: "Test",
      xpub: "tpubDFH9dgzveyD8",
      fingerprint: "73c5da",
      derivationPath: "m/48'/1'/0'/2'",
      orderIndex: 0
    )
    #expect(!invalidFP.isValidFingerprint)
  }
}
