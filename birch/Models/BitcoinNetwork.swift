import Foundation

enum BitcoinNetwork: String, CaseIterable, Codable, Identifiable {
  case mainnet = "bitcoin"
  case testnet4
  case testnet3 = "testnet"
  case signet

  var id: String {
    rawValue
  }

  var displayName: String {
    switch self {
    case .mainnet: "Mainnet"
    case .testnet4: "Testnet4"
    case .testnet3: "Testnet3"
    case .signet: "Signet"
    }
  }

  var coinType: Int {
    switch self {
    case .mainnet: 0
    case .testnet4, .testnet3, .signet: 1
    }
  }

  var defaultElectrumHost: String? {
    switch self {
    case .mainnet: nil
    case .testnet4: "testnet4.mempool.space"
    case .testnet3: "electrum.blockstream.info"
    case .signet: "signet.mempool.space"
    }
  }

  var defaultElectrumPort: UInt16 {
    switch self {
    case .mainnet: 50002
    case .testnet4: 40002
    case .testnet3: 60002
    case .signet: 60602
    }
  }

  var usesSSL: Bool {
    switch self {
    default: true
    }
  }

  var defaultElectrumURL: String? {
    guard let host = defaultElectrumHost else { return nil }
    let proto = usesSSL ? "ssl" : "tcp"
    return "\(proto)://\(host):\(defaultElectrumPort)"
  }

  var addressPrefix: String {
    switch self {
    case .mainnet: "bc1"
    case .testnet4, .testnet3, .signet: "tb1"
    }
  }

  var xpubPrefix: String {
    switch self {
    case .mainnet: "xpub"
    case .testnet4, .testnet3, .signet: "tpub"
    }
  }

  /// BIP48 derivation path for P2WSH multisig
  var bip48DerivationPath: String {
    "m/48'/\(coinType)'/0'/2'"
  }

  /// Mempool.space base URL path for this network
  var mempoolPath: String {
    switch self {
    case .mainnet: ""
    case .testnet4: "/testnet4"
    case .testnet3: "/testnet"
    case .signet: "/signet"
    }
  }

  /// Block explorer base URL, using custom host or defaulting to mempool.space
  func explorerBaseURL(customHost: String? = nil) -> String {
    let host = (customHost?.isEmpty == false) ? customHost! : "mempool.space"
    return "https://\(host)\(mempoolPath)"
  }

  /// Full block explorer URL for a transaction
  func explorerTxURL(txid: String, customHost: String? = nil) -> URL? {
    URL(string: "\(explorerBaseURL(customHost: customHost))/tx/\(txid)")
  }

  /// Full block explorer URL for an address
  func explorerAddressURL(address: String, customHost: String? = nil) -> URL? {
    URL(string: "\(explorerBaseURL(customHost: customHost))/address/\(address)")
  }
}
