import Foundation

struct AddressItem: Identifiable, Equatable {
  let index: UInt32
  let address: String
  let isUsed: Bool
  let isChange: Bool

  var id: String {
    "\(isChange ? "change" : "receive"):\(index)"
  }

  var truncatedAddress: String {
    guard address.count > 20 else { return address }
    return "\(address.prefix(10))...\(address.suffix(10))"
  }
}
