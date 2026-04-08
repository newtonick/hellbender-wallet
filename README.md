<p align="center">
  <img src="https://hellbenderwallet.com/assets/AppIcon-og.png" alt="Hellbender" width="128" height="128" style="border-radius: 24px;" />
</p>

<h1 align="center">Hellbender</h1>

<p align="center">
  <em>Travel to your private keys and leave your laptop at home.</em>
</p>

<p align="center">
  <img src="https://hellbenderwallet.com/assets/screenshots/welcome.png" alt="Welcome" width="150" />
  <img src="https://hellbenderwallet.com/assets/screenshots/transactions.png" alt="Transactions" width="150" />
  <img src="https://hellbenderwallet.com/assets/screenshots/multisig-config.png" alt="Multisig Config" width="150" />
  <img src="https://hellbenderwallet.com/assets/screenshots/import-descriptor.png" alt="Import Descriptor" width="150" />
  <img src="https://hellbenderwallet.com/assets/screenshots/review-wallet.png" alt="Review Wallet" width="150" />
</p>

---

Hellbender is an iOS Bitcoin multisig coordinator written in Swift. It operates as a **watch-only wallet** — private keys never touch your phone. Coordinate signing across air-gapped hardware wallets using animated QR codes, bringing cold storage security with mobile convenience.

## Features

- **Watch-only architecture** — only public descriptors are stored on the device
- **Air-gapped QR signing** — UR and BBQR animated QR codes for PSBT exchange
- **Configurable M-of-N multisig** — 2-of-3, 3-of-5, and beyond
- **Full BIP-174 PSBT workflows** — create, sign, combine, and broadcast
- **UTXO management** — coin control and coin freezing
- **RBF fee bumping** — replace-by-fee support for stuck transactions
- **Multi-network support** — mainnet, testnet3, testnet4, and signet
- **Biometric security** — Face ID / Touch ID lock
- **Descriptor import/export** — QR scan, clipboard, and PDF export
- **Electrum server integration** — connect to your own node or a public server
- **Multi-wallet profiles** — manage multiple wallets in one app

## Building

### Requirements

- Xcode 16.2+
- iOS 18.6+ deployment target
- Swift 5.0

### Dependencies

All dependencies are managed via Swift Package Manager and resolve automatically:

| Package | Purpose |
|---------|---------|
| [BitcoinDevKit (bdk-swift)](https://github.com/bitcoindevkit/bdk-swift) | Bitcoin operations |
| [URKit](https://github.com/BlockchainCommons/URKit) | UR encoding/decoding |
| [URUI](https://github.com/BlockchainCommons/URUI) | QR display and scanning |
| [Bbqr](https://github.com/bitcoinppl/bbqr-swift) | BBQR encoding |

### Build Steps

1. Clone the repository
   ```bash
   git clone https://github.com/newtonick/hellbender-wallet.git
   cd hellbender-wallet
   ```
2. Open `hellbender.xcodeproj` in Xcode
3. SPM dependencies resolve automatically on first open
4. Build and run on a simulator or device

For reproducible release builds, see [Reproducible Builds](#reproducible-builds) below.

### CI

GitHub Actions runs `xcodebuild clean build analyze` on every push and pull request to `main`. A separate [reproducibility verification workflow](.github/workflows/reproducible-build-check.yml) builds the project twice, normalizes both outputs, and compares them to catch non-determinism regressions.

### Reproducible Builds

Hellbender supports **functionally equivalent** reproducible builds. Given the same source code and Xcode version, two independent builds will produce the same compiled logic after normalization. Certain metadata bytes (Mach-O UUIDs, timestamps, build-machine identifiers) are expected to differ and are zeroed by the normalization step.

**What IS reproducible** (after normalization): all code-bearing sections, resources, and application logic.

**What is NOT reproducible**: code signing timestamps, Mach-O LC_UUID values, Xcode build-machine metadata, App Store .ipa files (Apple re-signs and applies FairPlay DRM).

#### Prerequisites

- Exact Xcode version matching `.xcode-version` (currently 16.2)
- macOS with the matching SDK

#### Producing a verifiable build

```bash
./scripts/build-release.sh
```

This creates an unsigned archive at `/tmp/hellbender-build/hellbender.xcarchive`.

#### Verifying two builds

```bash
# Normalize both builds
./scripts/normalize-app.sh /path/to/build1.app
./scripts/normalize-app.sh /path/to/build2.app

# Compare
./scripts/compare-builds.sh /path/to/build1.app /path/to/build2.app
```

The comparison exits 0 if the builds are functionally equivalent, 1 if code differences are found.

## Links

- **Website**: [hellbenderwallet.com](https://hellbenderwallet.com)
- **TestFlight Beta**: [Join the beta](https://testflight.apple.com/join/PuHVwJDJ)
- **Author**: [newtonick](https://github.com/newtonick/hellbender-wallet/)

## License

MIT License — see [LICENSE](LICENSE) for details.

Hellbender's dependencies use permissive licenses compatible with MIT:
bdk-swift (MIT/Apache-2.0), URKit (BSD-2-Clause-Patent), URUI (BSD-2-Clause-Patent), Bbqr (Apache-2.0).
