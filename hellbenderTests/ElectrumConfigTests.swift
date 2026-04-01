import BitcoinDevKit
import Foundation
@testable import hellbender
import Testing

struct ElectrumConfigTests {
  @Test func defaultTestnet4Config() {
    let config = ElectrumConfig(network: .testnet4)
    #expect(config.host == "testnet4.mempool.space")
    #expect(config.port == 40002)
    #expect(config.useSSL == true)
    #expect(config.url == "ssl://testnet4.mempool.space:40002")
  }

  @Test func defaultMainnetConfig() {
    let config = ElectrumConfig(network: .mainnet)
    #expect(config.host == "") // Mainnet requires user-provided server
    #expect(config.port == 50002)
    #expect(config.useSSL == true)
  }

  @Test func defaultTestnet3Config() {
    let config = ElectrumConfig(network: .testnet3)
    #expect(config.host == "electrum.blockstream.info")
    #expect(config.port == 51002)
    #expect(config.useSSL == true)
  }

  @Test func customConfig() {
    let config = ElectrumConfig(host: "myserver.com", port: 12345, useSSL: true)
    #expect(config.url == "ssl://myserver.com:12345")
  }

  @Test func networkDefaultURLs() {
    for network in BitcoinNetwork.allCases {
      let config = ElectrumConfig(network: network)
      #expect(config.port > 0)
      #expect(!config.url.isEmpty)

      if network == .mainnet {
        // Mainnet has no default host — requires user input
        #expect(config.host == "")
      } else {
        #expect(!config.host.isEmpty)
      }

      // SSL networks should have ssl:// prefix
      if network.usesSSL {
        #expect(config.url.hasPrefix("ssl://"))
      } else {
        #expect(config.url.hasPrefix("tcp://"))
      }
    }
  }

  @Test func networkSwitchUpdatesDefaults() {
    let testnet4Config = ElectrumConfig(network: .testnet4)
    let mainnetConfig = ElectrumConfig(network: .mainnet)

    #expect(testnet4Config.port != mainnetConfig.port)
    #expect(testnet4Config.url != mainnetConfig.url)
  }

  @Test func fetchRealFeeRatesFromMempoolSpace() throws {
    // Connect directly to testnet4 mempool space
    let config = ElectrumConfig(host: "testnet4.mempool.space", port: 40002, useSSL: true)
    let client = try ElectrumClient(url: config.url)

    let highRaw = try? client.estimateFee(number: 1)
    let medRaw = try? client.estimateFee(number: 6)
    let lowRaw = try? client.estimateFee(number: 144)

    print("RAW FEES RETURNED BY BDK: High: \(String(describing: highRaw)), Med: \(String(describing: medRaw)), Low: \(String(describing: lowRaw))")
  }
}
