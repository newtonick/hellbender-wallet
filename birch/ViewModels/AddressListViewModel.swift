import Foundation
import Observation

@Observable
@MainActor
final class AddressListViewModel {
  var receiveAddresses: [AddressItem] = []
  var changeAddresses: [AddressItem] = []
  var selectedTab: AddressTab = .receive
  private var expectedProfileId: UUID?

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

  func loadAddresses(for profileId: UUID) {
    expectedProfileId = profileId
    guard bitcoinService.currentProfile?.id == expectedProfileId else {
      receiveAddresses = []
      changeAddresses = []
      return
    }
    receiveAddresses = bitcoinService.getAddresses(keychain: .external)
    changeAddresses = bitcoinService.getAddresses(keychain: .internal)
  }
}
