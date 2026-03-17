import Bbqr
import SwiftUI

struct BumpFeeView: View {
  @State var viewModel: BumpFeeViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        switch viewModel.currentStep {
        case .feeInput:
          BumpFeeInputView(viewModel: viewModel)
        case .psbtDisplay:
          BumpFeePSBTDisplayView(viewModel: viewModel)
        case .psbtScan:
          BumpFeePSBTScanView(viewModel: viewModel)
        case .broadcast:
          BumpFeeBroadcastView(viewModel: viewModel, dismiss: dismiss)
        }
      }
      .navigationTitle("Bump Fee")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .alert("Error", isPresented: .init(
        get: { viewModel.errorMessage != nil },
        set: { if !$0 { viewModel.errorMessage = nil } }
      )) {
        Button("OK") { viewModel.errorMessage = nil }
      } message: {
        Text(viewModel.errorMessage ?? "")
      }
    }
  }
}

// MARK: - Fee Input

private struct BumpFeeInputView: View {
  @Bindable var viewModel: BumpFeeViewModel

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        // Original fee info
        VStack(spacing: 12) {
          DetailRow(label: "Original Fee") {
            Text(viewModel.originalFee.formattedSats)
              .font(.hbMono())
              .foregroundStyle(Color.hbTextPrimary)
          }

          if let rate = viewModel.originalFeeRate {
            DetailRow(label: "Original Fee Rate") {
              Text("\(String(format: "%.1f", rate)) sat/vB")
                .font(.hbMono())
                .foregroundStyle(Color.hbTextPrimary)
            }
          }
        }
        .hbCard()

        // New fee rate input
        VStack(alignment: .leading, spacing: 8) {
          Text("New Fee Rate (sat/vB)")
            .font(.hbLabel())
            .foregroundStyle(Color.hbTextSecondary)

          TextField("e.g. 5", text: $viewModel.newFeeRate)
            .keyboardType(.numberPad)
            .font(.hbMono())
            .padding(12)
            .background(Color.hbSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.hbTextPrimary)
            .onChange(of: viewModel.newFeeRate) { _, newValue in
              let filtered = newValue.filter(\.isWholeNumber)
              if filtered != newValue { viewModel.newFeeRate = filtered }
            }

          if let fees = viewModel.recommendedFees {
            HStack(spacing: 8) {
              FeePresetButton(label: "High", rate: fees.fastest) {
                viewModel.newFeeRate = "\(Int(ceil(fees.fastest)))"
              }
              FeePresetButton(label: "Medium", rate: fees.hour) {
                viewModel.newFeeRate = "\(Int(ceil(fees.hour)))"
              }
            }
          }

          if let original = viewModel.originalFeeRate, !viewModel.newFeeRate.isEmpty, !viewModel.isValidFeeRate {
            Text("Must be higher than \(String(format: "%.1f", original)) sat/vB")
              .font(.hbBody(12))
              .foregroundStyle(.red)
          }
        }
        .hbCard()

        Button(action: {
          Task { await viewModel.createBumpPSBT() }
        }) {
          if viewModel.isProcessing {
            ProgressView()
              .tint(.white)
              .frame(maxWidth: .infinity, minHeight: 48)
          } else {
            Text("Create Replacement")
              .hbPrimaryButton()
          }
        }
        .disabled(!viewModel.isValidFeeRate || viewModel.isProcessing)
        .padding(.horizontal, 24)
      }
      .padding(16)
    }
    .background(Color.hbBackground)
    .task {
      await viewModel.fetchFeeRates()
    }
  }
}

private struct FeePresetButton: View {
  let label: String
  let rate: Float
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Text(label)
          .font(.hbLabel(11))
        Text("\(Int(ceil(rate))) sat/vB")
          .font(.hbMono(12))
      }
      .foregroundStyle(Color.hbBitcoinOrange)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Color.hbBitcoinOrange.opacity(0.1))
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }
}

// MARK: - PSBT Display

private struct BumpFeePSBTDisplayView: View {
  @Bindable var viewModel: BumpFeeViewModel
  @State private var showAdvanced = false
  @State private var framesPerSecond: Double = 4.0
  @State private var qrEncoding: QREncoding = .ur
  @State private var qrDensity: QRDensity = .medium
  @State private var qrDisplayHeight: CGFloat = 700

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        SignatureProgressView(
          collected: viewModel.signaturesCollected,
          required: viewModel.requiredSignatures,
          signerStatus: viewModel.signerStatus
        )

        if !viewModel.psbtBytes.isEmpty {
          GeometryReader { geo in
            let maxSide = min(geo.size.width, geo.size.height)
            Group {
              if qrEncoding == .ur {
                URDisplaySheet(
                  data: viewModel.psbtBytes,
                  urType: "crypto-psbt",
                  framesPerSecond: framesPerSecond,
                  maxFragmentLen: qrDensity.urFragmentLen
                )
                .id(qrDensity.urFragmentLen)
              } else {
                BBQRDisplayView(
                  data: viewModel.psbtBytes,
                  fileType: .psbt,
                  framesPerSecond: framesPerSecond,
                  maxVersion: qrDensity.bbqrMaxVersion
                )
                .id("\(qrDensity.rawValue)-bbqr")
              }
            }
            .frame(width: maxSide, height: maxSide)
            .padding(5)
            .background(Color.white)
            .shadow(color: Color.hbBitcoinOrange.opacity(0.2), radius: 20)
            .frame(maxWidth: .infinity)
          }
          .aspectRatio(1, contentMode: .fit)
          .frame(maxHeight: 700)
          .background(GeometryReader { geo in
            Color.clear.onAppear { qrDisplayHeight = geo.size.height }
              .onChange(of: geo.size.height) { _, h in qrDisplayHeight = h }
          })
        }

        Text("Scan this QR code with your signing device")
          .font(.hbBody(14))
          .foregroundStyle(Color.hbTextSecondary)
          .multilineTextAlignment(.center)

        DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
          VStack(spacing: 12) {
            HStack {
              Text("QR Encoding")
                .font(.hbLabel())
                .foregroundStyle(Color.hbTextSecondary)
              Spacer()
              Picker("", selection: $qrEncoding) {
                ForEach(QREncoding.allCases, id: \.self) { encoding in
                  Text(encoding.rawValue).tag(encoding)
                }
              }
              .pickerStyle(.segmented)
              .frame(width: 160)
            }

            HStack {
              Text("QR Frame Rate")
                .font(.hbLabel())
                .foregroundStyle(Color.hbTextSecondary)
              Spacer()
              Text("\(Int(framesPerSecond)) FPS")
                .font(.hbMono(14))
                .foregroundStyle(Color.hbBitcoinOrange)
            }

            Slider(value: $framesPerSecond, in: 1 ... 10, step: 1)
              .tint(Color.hbBitcoinOrange)

            HStack {
              Text("QR Density")
                .font(.hbLabel())
                .foregroundStyle(Color.hbTextSecondary)
              Spacer()
              Picker("", selection: $qrDensity) {
                ForEach(QRDensity.available(forHeight: qrDisplayHeight), id: \.self) { density in
                  Text(density.rawValue).tag(density)
                }
              }
              .pickerStyle(.segmented)
              .frame(width: QRDensity.available(forHeight: qrDisplayHeight).count > 3 ? 260 : 200)
            }
          }
          .padding(.top, 8)
        }
        .font(.hbBody(14))
        .foregroundStyle(Color.hbTextSecondary)
        .padding(.horizontal, 24)

        Button(action: {
          if viewModel.needsMoreSignatures {
            viewModel.currentStep = .psbtScan
          } else {
            viewModel.currentStep = .broadcast
          }
        }) {
          Text(viewModel.needsMoreSignatures ? "Scan Signed PSBT" : "Broadcast Transaction")
            .hbPrimaryButton()
        }
        .padding(.horizontal, 24)

        Button(action: {
          UIPasteboard.general.string = viewModel.psbtBase64
        }) {
          Label("Copy Base64", systemImage: "doc.on.doc")
            .font(.hbBody(14))
            .foregroundStyle(Color.hbSteelBlue)
        }
        .padding(.bottom, 32)
      }
      .padding(.top, 8)
    }
    .background(Color.hbBackground)
  }
}

// MARK: - PSBT Scan

private struct BumpFeePSBTScanView: View {
  @Bindable var viewModel: BumpFeeViewModel
  @State private var showManualInput = false
  @State private var manualPSBTBase64 = ""

  var body: some View {
    VStack(spacing: 24) {
      Text("Scan Signed PSBT")
        .font(.hbDisplay(22))
        .foregroundStyle(Color.hbTextPrimary)

      SignatureProgressView(
        collected: viewModel.signaturesCollected,
        required: viewModel.requiredSignatures
      )

      URScannerSheet { result in
        if case let .psbt(data) = result {
          Task { await viewModel.handleSignedPSBT(data) }
        }
      }
      .aspectRatio(1, contentMode: .fit)
      .frame(maxHeight: 500)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .padding(.horizontal, 24)

      Button(action: { showManualInput = true }) {
        Label("Paste Base64 PSBT", systemImage: "doc.on.clipboard")
          .font(.hbBody(14))
          .foregroundStyle(Color.hbSteelBlue)
      }

      Spacer()

      Button(action: { viewModel.currentStep = .psbtDisplay }) {
        Text("Back to QR Display")
          .font(.hbBody(16))
          .foregroundStyle(Color.hbTextSecondary)
      }
      .padding(.bottom, 32)
    }
    .padding(.top, 16)
    .background(Color.hbBackground)
    .alert("Paste Signed PSBT", isPresented: $showManualInput) {
      TextField("Base64 PSBT", text: $manualPSBTBase64)
      Button("Import") {
        if let data = Data(base64Encoded: manualPSBTBase64) {
          Task { await viewModel.handleSignedPSBT(data) }
        }
      }
      Button("Cancel", role: .cancel) {}
    }
  }
}

// MARK: - Broadcast

private struct BumpFeeBroadcastView: View {
  @Bindable var viewModel: BumpFeeViewModel
  let dismiss: DismissAction

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      if viewModel.broadcastTxid.isEmpty {
        // Ready to broadcast
        Image(systemName: "arrow.up.circle.fill")
          .font(.system(size: 56))
          .foregroundStyle(Color.hbBitcoinOrange)

        Text("Ready to Broadcast")
          .font(.hbDisplay(22))
          .foregroundStyle(Color.hbTextPrimary)

        Text("Your replacement transaction is fully signed and ready to broadcast.")
          .font(.hbBody())
          .foregroundStyle(Color.hbTextSecondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)

        Button(action: {
          Task { await viewModel.broadcast() }
        }) {
          if viewModel.isProcessing {
            ProgressView()
              .tint(.white)
              .frame(maxWidth: .infinity, minHeight: 48)
          } else {
            Text("Broadcast Transaction")
              .hbPrimaryButton()
          }
        }
        .disabled(viewModel.isProcessing)
        .padding(.horizontal, 24)
      } else {
        // Success
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 56))
          .foregroundStyle(Color.hbSuccess)

        Text("Replacement Broadcast!")
          .font(.hbDisplay(22))
          .foregroundStyle(Color.hbTextPrimary)

        VStack(spacing: 8) {
          Text("New Transaction ID")
            .font(.hbLabel())
            .foregroundStyle(Color.hbTextSecondary)

          Text(viewModel.broadcastTxid)
            .font(.hbMono(11))
            .foregroundStyle(Color.hbTextPrimary)
            .textSelection(.enabled)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }

        Button(action: {
          UIPasteboard.general.string = viewModel.broadcastTxid
        }) {
          Label("Copy Transaction ID", systemImage: "doc.on.doc")
            .font(.hbBody(14))
            .foregroundStyle(Color.hbSteelBlue)
        }

        Button(action: { dismiss() }) {
          Text("Done")
            .hbPrimaryButton()
        }
        .padding(.horizontal, 24)
      }

      Spacer()
    }
    .background(Color.hbBackground)
  }
}

// MARK: - Detail Row (local)

private struct DetailRow<Content: View>: View {
  let label: String
  @ViewBuilder let content: Content

  var body: some View {
    HStack {
      Text(label)
        .font(.hbLabel())
        .foregroundStyle(Color.hbTextSecondary)
      Spacer()
      content
    }
  }
}
