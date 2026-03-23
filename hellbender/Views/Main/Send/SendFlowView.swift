import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SendFlowView: View {
  @Binding var selectedTab: Int
  @Binding var resumePSBT: SavedPSBT?
  @State private var viewModel = SendViewModel()
  @Query private var frozenUTXOs: [FrozenUTXO]
  @Environment(\.modelContext) private var modelContext
  @State private var bumpFeeViewModel: BumpFeeViewModel?
  var body: some View {
    NavigationStack {
      ZStack {
        Color.hbBackground.ignoresSafeArea()

        VStack(spacing: 0) {
          HStack {
            Text("Send")
              .font(.hbAmountLarge)
              .foregroundStyle(Color.hbTextPrimary)

            Spacer()

            if viewModel.currentStep == .recipients {
              Menu {
                Button(action: { viewModel.showLoadPSBT = true }) {
                  Label("Saved PSBTs", systemImage: "tray.and.arrow.down")
                }
                Button(action: { viewModel.showImportPSBTQR = true }) {
                  Label("Import PSBT via QR", systemImage: "qrcode.viewfinder")
                }
                Button(action: { viewModel.showImportPSBTFile = true }) {
                  Label("Import PSBT via File", systemImage: "doc")
                }
              } label: {
                Image(systemName: "ellipsis.circle")
                  .font(.system(size: 18))
                  .foregroundStyle(Color.hbBitcoinOrange)
              }
            }
          }
          .padding(.horizontal, 16)
          .padding(.top, 8)
          .padding(.bottom, 4)

          Group {
            switch viewModel.currentStep {
            case .recipients:
              SendRecipientsView(viewModel: viewModel)
            case .review:
              SendReviewView(viewModel: viewModel)
            case .psbtDisplay:
              PSBTDisplayView(viewModel: viewModel)
            case .psbtScan:
              PSBTScanView(viewModel: viewModel)
            case .broadcast:
              BroadcastResultView(viewModel: viewModel, selectedTab: $selectedTab)
            }
          }
        }
      }
      .navigationTitle("")
      .alert("Error", isPresented: .init(
        get: { viewModel.errorMessage != nil },
        set: { if !$0 { viewModel.errorMessage = nil } }
      )) {
        Button("OK") { viewModel.errorMessage = nil }
      } message: {
        Text(viewModel.errorMessage ?? "")
      }
    }
    .onAppear {
      loadFrozenOutpoints()
      viewModel.loadBalance()
      if let saved = resumePSBT {
        viewModel.loadSavedPSBT(saved)
        resumePSBT = nil
      }
    }
    .onChange(of: frozenUTXOs.count) {
      loadFrozenOutpoints()
      viewModel.loadBalance()
    }
    .onChange(of: BitcoinService.shared.currentProfile?.id) {
      viewModel.reset()
      loadFrozenOutpoints()
      viewModel.loadBalance()
    }
    .onChange(of: resumePSBT) { _, saved in
      if let saved {
        viewModel.loadSavedPSBT(saved)
        resumePSBT = nil
      }
    }
    .sheet(isPresented: $viewModel.showLoadPSBT) {
      SavedPSBTListView(viewModel: viewModel) { savedPSBT in
        bumpFeeViewModel = BumpFeeViewModel(savedPSBT: savedPSBT)
      }
    }
    .sheet(item: $bumpFeeViewModel) { vm in
      BumpFeeView(viewModel: vm)
    }
    .sheet(isPresented: $viewModel.showImportPSBTQR) {
      ImportPSBTQRSheet(viewModel: viewModel)
    }
    .fileImporter(
      isPresented: $viewModel.showImportPSBTFile,
      allowedContentTypes: [.data, .plainText],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case let .success(urls):
        guard let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else {
          viewModel.errorMessage = "Unable to access file"
          return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
          let data = try Data(contentsOf: url)
          viewModel.importPSBT(data, source: "File", context: modelContext)
        } catch {
          viewModel.errorMessage = "Failed to read file: \(error.localizedDescription)"
        }
      case let .failure(error):
        viewModel.errorMessage = "File import failed: \(error.localizedDescription)"
      }
    }
  }

  private func loadFrozenOutpoints() {
    guard let walletID = BitcoinService.shared.currentProfile?.id else { return }
    viewModel.frozenOutpoints = Set(frozenUTXOs.filter { $0.walletID == walletID }.map(\.outpoint))
  }
}

// MARK: - Import PSBT via QR Sheet

struct ImportPSBTQRSheet: View {
  @Bindable var viewModel: SendViewModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    NavigationStack {
      URScannerSheet { result in
        switch result {
        case let .psbt(data):
          viewModel.importPSBT(data, source: "QR", context: modelContext)
          dismiss()
        default:
          viewModel.errorMessage = "Scanned QR is not a valid PSBT"
          dismiss()
        }
      }
      .navigationTitle("Import PSBT")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .foregroundStyle(Color.hbBitcoinOrange)
        }
      }
    }
  }
}
