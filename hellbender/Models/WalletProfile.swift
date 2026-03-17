import Foundation
import SwiftData

@Model
final class WalletProfile {
  var id: UUID
  var name: String
  var requiredSignatures: Int
  var totalCosigners: Int
  var externalDescriptor: String
  var internalDescriptor: String
  var network: String
  var createdAt: Date
  var isActive: Bool
  var addressGapLimit: Int
  var electrumHost: String
  var electrumPort: Int
  var electrumSSL: Int // 0 = network default, 1 = TCP, 2 = SSL
  var blockExplorerHost: String // empty = mempool.space

  @Relationship(deleteRule: .cascade, inverse: \CosignerInfo.wallet)
  var cosigners: [CosignerInfo]

  init(
    id: UUID = UUID(),
    name: String,
    requiredSignatures: Int,
    totalCosigners: Int,
    externalDescriptor: String,
    internalDescriptor: String,
    network: BitcoinNetwork = .testnet4,
    isActive: Bool = false,
    addressGapLimit: Int = 50,
    electrumHost: String = "",
    electrumPort: Int = 0,
    electrumSSL: Int = 0,
    blockExplorerHost: String = ""
  ) {
    self.id = id
    self.name = name
    self.requiredSignatures = requiredSignatures
    self.totalCosigners = totalCosigners
    self.externalDescriptor = externalDescriptor
    self.internalDescriptor = internalDescriptor
    self.network = network.rawValue
    createdAt = Date()
    self.isActive = isActive
    self.addressGapLimit = addressGapLimit
    self.electrumHost = electrumHost
    self.electrumPort = electrumPort
    self.electrumSSL = electrumSSL
    self.blockExplorerHost = blockExplorerHost
    cosigners = []
  }

  var bitcoinNetwork: BitcoinNetwork {
    BitcoinNetwork(rawValue: network) ?? .testnet4
  }

  var electrumConfig: ElectrumConfig {
    let net = bitcoinNetwork
    let host = electrumHost.isEmpty ? (net.defaultElectrumHost ?? "") : electrumHost
    let port = electrumPort > 0 ? UInt16(electrumPort) : net.defaultElectrumPort
    let ssl: Bool = switch electrumSSL {
    case 1: false // TCP
    case 2: true // SSL
    default: net.usesSSL // 0 = network default
    }
    return ElectrumConfig(host: host, port: port, useSSL: ssl)
  }

  var multisigDescription: String {
    "\(requiredSignatures)-of-\(totalCosigners)"
  }
}
