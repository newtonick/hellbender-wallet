import AVFoundation
import Bbqr
import Combine
import SwiftUI
import URKit
import URUI

struct URScannerSheet: View {
  let onResult: (AppURResult) -> Void

  @StateObject private var videoSession: URVideoSession
  @StateObject private var scanState: URScanState
  @State private var estimatedPercent: Double = 0
  @State private var bbqrJoiner = ContinuousJoiner()
  @State private var bbqrMode = false
  @State private var bbqrPartsTotal: UInt16 = 0
  @State private var bbqrPartsReceived: UInt16 = 0
  @State private var currentZoom: CGFloat = 1.0
  @State private var baseZoom: CGFloat = 1.0

  private let codesPublisher = URCodesPublisher()

  init(onResult: @escaping (AppURResult) -> Void) {
    self.onResult = onResult
    let publisher = URCodesPublisher()
    _videoSession = StateObject(wrappedValue: URVideoSession(codesPublisher: publisher))
    _scanState = StateObject(wrappedValue: URScanState(codesPublisher: publisher))
  }

  var body: some View {
    ZStack {
      Color.hbBackground.ignoresSafeArea()

      VStack(spacing: 16) {
        URVideo(videoSession: videoSession)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .overlay(ScannerOverlay())
          .gesture(
            MagnifyGesture()
              .onChanged { value in
                guard let device = videoSession.currentCaptureDevice else { return }
                let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
                let newZoom = min(max(baseZoom * value.magnification, 1.0), maxZoom)
                try? device.lockForConfiguration()
                device.videoZoomFactor = newZoom
                device.unlockForConfiguration()
                currentZoom = newZoom
              }
              .onEnded { _ in
                baseZoom = currentZoom
              }
          )

        if displayProgress > 0, displayProgress < 1 {
          VStack(spacing: 4) {
            ProgressView(value: displayProgress)
              .tint(Color.hbBitcoinOrange)

            Text("\(Int(displayProgress * 100))% received")
              .font(.hbLabel())
              .foregroundStyle(Color.hbTextSecondary)
          }
          .padding(.horizontal, 24)
        }
      }
    }
    .onAppear {
      configureCameraForCloseScanning()
    }
    .onReceive(scanState.resultPublisher) { result in
      switch result {
      case let .ur(ur):
        let appResult = URService.processUR(ur)
        onResult(appResult)
      case let .progress(progress):
        estimatedPercent = progress.estimatedPercentComplete
      case let .other(code):
        if let hdKeyResult = URService.parseTextEncodedXpub(code) {
          onResult(hdKeyResult)
        } else {
          handlePossibleBBQR(code)
        }
      case .reject, .failure:
        break
      }
    }
  }

  private var displayProgress: Double {
    if bbqrMode, bbqrPartsTotal > 0 {
      return Double(bbqrPartsReceived) / Double(bbqrPartsTotal)
    }
    return estimatedPercent
  }

  private func configureCameraForCloseScanning() {
    guard let device = videoSession.currentCaptureDevice else { return }
    try? device.lockForConfiguration()
    if device.isAutoFocusRangeRestrictionSupported {
      device.autoFocusRangeRestriction = .near
    }
    if device.isFocusModeSupported(.continuousAutoFocus) {
      device.focusMode = .continuousAutoFocus
    }
    device.unlockForConfiguration()
  }

  private func handlePossibleBBQR(_ code: String) {
    guard code.hasPrefix("B$") else { return }

    do {
      let result = try bbqrJoiner.addPart(part: code)
      switch result {
      case .notStarted:
        break
      case let .inProgress(partsLeft):
        bbqrMode = true
        if bbqrPartsTotal == 0 {
          bbqrPartsTotal = partsLeft + 1
        }
        bbqrPartsReceived = bbqrPartsTotal - partsLeft
      case let .complete(joined):
        let data = joined.data()
        let fileType = joined.fileType()
        bbqrMode = false
        switch fileType {
        case .psbt:
          onResult(.psbt(data))
        case .transaction:
          onResult(.unknown("bbqr-transaction"))
        case .json, .cbor, .unicodeText:
          onResult(.unknown("bbqr-\(fileType)"))
        }
      }
    } catch {
      print("BBQRScan: Error processing part: \(error)")
    }
  }
}

struct ScannerOverlay: View {
  var body: some View {
    GeometryReader { geo in
      let size = min(geo.size.width, geo.size.height) * 0.7
      let cornerLength: CGFloat = 24
      let origin = CGPoint(
        x: (geo.size.width - size) / 2,
        y: (geo.size.height - size) / 2
      )

      Path { path in
        // Top-left
        path.move(to: CGPoint(x: origin.x, y: origin.y + cornerLength))
        path.addLine(to: CGPoint(x: origin.x, y: origin.y))
        path.addLine(to: CGPoint(x: origin.x + cornerLength, y: origin.y))

        // Top-right
        path.move(to: CGPoint(x: origin.x + size - cornerLength, y: origin.y))
        path.addLine(to: CGPoint(x: origin.x + size, y: origin.y))
        path.addLine(to: CGPoint(x: origin.x + size, y: origin.y + cornerLength))

        // Bottom-right
        path.move(to: CGPoint(x: origin.x + size, y: origin.y + size - cornerLength))
        path.addLine(to: CGPoint(x: origin.x + size, y: origin.y + size))
        path.addLine(to: CGPoint(x: origin.x + size - cornerLength, y: origin.y + size))

        // Bottom-left
        path.move(to: CGPoint(x: origin.x + cornerLength, y: origin.y + size))
        path.addLine(to: CGPoint(x: origin.x, y: origin.y + size))
        path.addLine(to: CGPoint(x: origin.x, y: origin.y + size - cornerLength))
      }
      .stroke(Color.hbBitcoinOrange, lineWidth: 3)
    }
  }
}
