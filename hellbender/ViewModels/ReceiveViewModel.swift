import Foundation
import Observation

@Observable
final class ReceiveViewModel {
  var currentAddress: String = ""
  var addressIndex: UInt32 = 0
  var errorMessage: String?

  private var bitcoinService: BitcoinService {
    BitcoinService.shared
  }

  func loadAddress() {
    do {
      let (address, index) = try bitcoinService.getNextAddress()
      currentAddress = address
      addressIndex = index
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func generateNewAddress() {
    do {
      let (address, index) = try bitcoinService.revealNextAddress()
      currentAddress = address
      addressIndex = index
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
