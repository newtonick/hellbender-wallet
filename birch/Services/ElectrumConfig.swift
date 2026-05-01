import Foundation

struct ElectrumConfig: Equatable {
  var host: String
  var port: UInt16
  var useSSL: Bool
  var allowInsecureSSL: Bool

  var url: String {
    let proto = useSSL ? "ssl" : "tcp"
    return "\(proto)://\(host):\(port)"
  }

  init(host: String, port: UInt16, useSSL: Bool, allowInsecureSSL: Bool = false) {
    self.host = host
    self.port = port
    self.useSSL = useSSL
    self.allowInsecureSSL = allowInsecureSSL
  }

  init(network: BitcoinNetwork) {
    host = network.defaultElectrumHost ?? ""
    port = network.defaultElectrumPort
    useSSL = network.usesSSL
    allowInsecureSSL = false
  }
}
