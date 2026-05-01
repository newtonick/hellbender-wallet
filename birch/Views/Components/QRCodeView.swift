import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeView: View {
  let content: String

  var body: some View {
    if let image = generateQRCode(from: content) {
      Image(uiImage: image)
        .interpolation(.none)
        .resizable()
        .scaledToFit()
    } else {
      Image(systemName: "qrcode")
        .font(.system(size: 48))
        .foregroundStyle(Color.hbTextSecondary)
    }
  }

  private func generateQRCode(from string: String) -> UIImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()

    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"

    guard let outputImage = filter.outputImage else { return nil }

    let scale = 10.0
    let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

    guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

    return UIImage(cgImage: cgImage)
  }
}
