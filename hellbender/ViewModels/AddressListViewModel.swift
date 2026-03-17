import Foundation
import Observation

@Observable
final class AddressListViewModel {
  var receiveAddresses: [AddressItem] = []
  var changeAddresses: [AddressItem] = []
  var selectedTab: AddressTab = .receive

  enum AddressTab: String, CaseIterable {
    case receive = "Receive"
    case change = "Change"
  }

  var displayedAddresses: [AddressItem] {
    selectedTab == .receive ? receiveAddresses : changeAddresses
  }

  private var bitcoinService: BitcoinService {
    BitcoinService.shared
  }

  func loadAddresses() {
    receiveAddresses = bitcoinService.getAddresses(keychain: .external)
    changeAddresses = bitcoinService.getAddresses(keychain: .internal)
  }
}
