import Foundation

struct ElectrumConfig: Equatable {
  var host: String
  var port: UInt16
  var useSSL: Bool

  var url: String {
    let proto = useSSL ? "ssl" : "tcp"
    return "\(proto)://\(host):\(port)"
  }

  init(host: String, port: UInt16, useSSL: Bool) {
    self.host = host
    self.port = port
    self.useSSL = useSSL
  }

  init(network: BitcoinNetwork) {
    host = network.defaultElectrumHost ?? ""
    port = network.defaultElectrumPort
    useSSL = network.usesSSL
  }
}
