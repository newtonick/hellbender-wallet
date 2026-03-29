import Foundation
@testable import hellbender
import Testing

@MainActor
struct PSBTTests {
  // MARK: - Helpers

  private func loadFixture(_ name: String) -> String? {
    let bundle = Bundle(for: BundleToken.self)
    guard let path = bundle.path(forResource: name, ofType: "txt") else { return nil }
    return try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Existing Tests

  @Test func psbtBase64RoundTrip() {
    // A minimal valid base64 string
    let original = "cHNidP8BAFICAAAAAZ38ZijCcnkzwmZ2"
    guard let data = Data(base64Encoded: original) else {
      Issue.record("Failed to decode base64")
      return
    }
    let reencoded = data.base64EncodedString()
    #expect(reencoded == original)
  }

  @Test func psbtDataPreservesContent() {
    // Test that raw PSBT bytes survive encode/decode
    let testBytes: [UInt8] = [0x70, 0x73, 0x62, 0x74, 0xFF] // "psbt" magic + separator
    let data = Data(testBytes)
    let base64 = data.base64EncodedString()
    let decoded = Data(base64Encoded: base64)
    #expect(decoded == data)
  }

  @Test func loadTestPSBTFixture() {
    // Test that the fixture file can be loaded
    let bundle = Bundle(for: BundleToken.self)
    if let path = bundle.path(forResource: "test_psbt_unsigned", ofType: "txt") {
      let content = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
      #expect(content != nil)
      #expect(content?.isEmpty == false)

      // Should be valid base64
      if let content {
        let data = Data(base64Encoded: content)
        #expect(data != nil)
      }
    }
  }

  // MARK: - Fixture-Based Tests

  @Test func psbtMagicBytes() {
    guard let base64 = loadFixture("test_psbt_unsigned"),
          let data = Data(base64Encoded: base64)
    else {
      Issue.record("Failed to load unsigned fixture")
      return
    }
    // PSBT magic bytes: 0x70736274FF ("psbt" + separator)
    let magic: [UInt8] = [0x70, 0x73, 0x62, 0x74, 0xFF]
    let prefix = Array(data.prefix(5))
    #expect(prefix == magic, "PSBT should start with magic bytes 0x70736274FF")
  }

  @Test func psbtBase64RoundTripWithFixture() {
    guard let base64 = loadFixture("test_psbt_unsigned"),
          let data = Data(base64Encoded: base64)
    else {
      Issue.record("Failed to load unsigned fixture")
      return
    }
    // Encode back to base64 and verify it matches
    let reencoded = data.base64EncodedString()
    #expect(reencoded == base64, "Base64 round-trip should be lossless")

    // Decode again and verify bytes match
    guard let redecoded = Data(base64Encoded: reencoded) else {
      Issue.record("Failed to re-decode base64")
      return
    }
    #expect(redecoded == data, "Double round-trip should preserve bytes")
  }

  @Test func partialFixtureHasMagicBytes() {
    guard let base64 = loadFixture("test_psbt_partial"),
          let data = Data(base64Encoded: base64)
    else {
      Issue.record("Failed to load partial fixture")
      return
    }
    let magic: [UInt8] = [0x70, 0x73, 0x62, 0x74, 0xFF]
    let prefix = Array(data.prefix(5))
    #expect(prefix == magic, "Partial PSBT should start with magic bytes")
  }

  @Test func partialFixtureDiffersFromUnsigned() {
    guard let unsignedBase64 = loadFixture("test_psbt_unsigned"),
          let partialBase64 = loadFixture("test_psbt_partial")
    else {
      Issue.record("Failed to load fixtures")
      return
    }
    // The partial fixture should differ from unsigned (it has additional signature data)
    #expect(unsignedBase64 != partialBase64, "Partial PSBT should differ from unsigned")

    guard let unsignedData = Data(base64Encoded: unsignedBase64),
          let partialData = Data(base64Encoded: partialBase64)
    else {
      Issue.record("Failed to decode fixtures")
      return
    }
    #expect(unsignedData != partialData, "Partial PSBT bytes should differ from unsigned")
  }

  // Note: BDK-level combine/finalize tests are covered by SigningFlowTests
  // using MockBitcoinService, since BDK is not linked to the test target.
}

/// Helper to access test bundle
private class BundleToken {}
