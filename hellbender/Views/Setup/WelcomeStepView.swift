import SwiftUI

struct WelcomeStepView: View {
  @Bindable var viewModel: SetupWizardViewModel

  var body: some View {
    VStack(spacing: 32) {
      Spacer()

      // Icon
      Image("WelcomeIcon")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(Color.hbBackground, lineWidth: 24)
            .blur(radius: 12)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(Color.hbBorder.opacity(0.5), lineWidth: 1)
        )

      VStack(spacing: 12) {
        Text("Hellbender Wallet")
          .font(.hbDisplay(34))
          .foregroundStyle(Color.hbTextPrimary)

        Text("A Bitcoin Multisig Coordinator")
          .font(.hbBody(17))
          .foregroundStyle(Color.hbTextSecondary)
      }

      VStack(alignment: .leading, spacing: 16) {
        FeatureRow(icon: "eye.fill", text: "Watch-only — no private keys stored")
        FeatureRow(icon: "person.3.fill", text: "Multi-signature security (M-of-N)")
        FeatureRow(icon: "qrcode.viewfinder", text: "Airgapped QR signing device support")
        FeatureRow(icon: "server.rack", text: "Connect to your own Electrum server")
        FeatureRow(icon: "wallet.bifold.fill", text: "Coordinate multiple wallets")
      }
      .padding(.horizontal, 24)

      Spacer()

      Button(action: { viewModel.goToNext() }) {
        Text("Get Started")
          .hbPrimaryButton()
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 32)
    }
  }
}

private struct FeatureRow: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 18))
        .foregroundStyle(Color.hbBitcoinOrange)
        .frame(width: 28)

      Text(text)
        .font(.hbBody(15))
        .foregroundStyle(Color.hbTextPrimary)
    }
  }
}
