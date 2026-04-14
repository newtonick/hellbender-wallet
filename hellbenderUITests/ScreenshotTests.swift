//
//  ScreenshotTests.swift
//  hellbenderUITests
//
//  Fastlane `snapshot` walker. Invoked by `bundle exec fastlane screenshots`
//  (see fastlane/Fastfile). Walks the app from Welcome through the main tabs,
//  calling `snapshot(...)` at each marketing stop.
//
//  Kept separate from hellbenderUITests.swift on purpose: the assertion-heavy
//  setup test validates that the flow still works, and this test is purely for
//  capturing images. The descriptor-import sequence is duplicated (not shared)
//  so each test fails in isolation.
//

import XCTest

final class ScreenshotTests: XCTestCase {
  var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments += ["-UITesting"]
  }

  override func tearDownWithError() throws {
    app = nil
  }

  @MainActor
  func testScreenshotTour() throws {
    setupSnapshot(app)
    app.launch()

    // MARK: 01 - Welcome
    let getStarted = app.buttons["Get Started"]
    XCTAssertTrue(getStarted.waitForExistence(timeout: 5), "Welcome screen should show 'Get Started' button")
    snapshot("01-Welcome")
    getStarted.tap()

    // MARK: 02 - Set Up Wallet (creation choice)
    let walletSetupTitle = app.staticTexts["Set Up Wallet"]
    XCTAssertTrue(walletSetupTitle.waitForExistence(timeout: 3), "Set Up Wallet screen should appear")
    sleep(1)
    snapshot("02-Wallet-Setup")

    // MARK: Walk the descriptor-import flow to reach a loaded wallet.
    // (Mirrors hellbenderUITests.swift `testSetupWalletViaDescriptorImport`.)

    let importCard = app.staticTexts["Import Descriptor"]
    XCTAssertTrue(importCard.waitForExistence(timeout: 3), "Creation choice should show 'Import Descriptor' option")
    importCard.tap()

    let importTitle = app.staticTexts["Import Descriptor"]
    XCTAssertTrue(importTitle.waitForExistence(timeout: 3), "Descriptor import screen should appear")

    let testDescriptor = "wsh(sortedmulti(1,[7a13a7b1/48'/1'/0'/2']tpubDETciRzaZyqww2dSAyT2j6tWgzREyiZEY2iZDPKDtqNpSEqqFS31DZUFFTFnayx7wLUVYx3V1R2AWhhWbFrnCukKZ1kmnn83Fn2xSf7hEaH/<0;1>/*,[30a36b52/48'/1'/0'/2']tpubDF6MPv2vWsbCo8c7rk4X32BPa5yuj4niem5Pr6isrd9cSdCkYETcGUmBSFY4ekTR1CRFmjn4eoYGrwPU19FffwEpX7Tda6BBmg91aiHKpmE/<0;1>/*))"

    let textEditor = app.textViews.firstMatch
    XCTAssertTrue(textEditor.waitForExistence(timeout: 3), "Descriptor text editor should exist")
    textEditor.tap()

    // Paste the descriptor instead of typing character-by-character.
    // typeText() is extremely slow on older simulators (e.g. iPhone 11 Pro
    // Max) for 350+ character strings and can cause downstream timeouts.
    UIPasteboard.general.string = testDescriptor
    textEditor.press(forDuration: 1.2)
    let pasteButton = app.menuItems["Paste"]
    if pasteButton.waitForExistence(timeout: 3) {
      pasteButton.tap()
    } else {
      // Fallback to typeText if paste menu doesn't appear
      textEditor.typeText(testDescriptor)
    }

    // Dismiss keyboard so network buttons are visible
    app.swipeDown()
    sleep(1)

    let testnet4Button = app.buttons["Testnet4"]
    if testnet4Button.waitForExistence(timeout: 5) {
      testnet4Button.tap()
    }

    let importButton = app.buttons["Import"]
    XCTAssertTrue(importButton.waitForExistence(timeout: 5), "Import button should exist")
    importButton.tap()

    // Descriptor parsing and BDK validation can take several seconds on
    // slower simulators (e.g. iPhone 11 Pro Max on x86_64).
    let nameTitle = app.staticTexts["Name Your Wallet"]
    XCTAssertTrue(nameTitle.waitForExistence(timeout: 30), "Wallet name screen should appear")

    let nameField = app.textFields["My Wallet"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3), "Wallet name text field should exist")
    nameField.tap()
    nameField.typeText("Hellbender")

    // In descriptor-import mode the button reads "Create Wallet" (not "Next")
    // and skips the Review screen, going straight to the loaded wallet.
    let createButton = app.buttons["Create Wallet"]
    XCTAssertTrue(createButton.waitForExistence(timeout: 3), "Create Wallet button should exist")
    createButton.tap()

    // Wait for the main Transactions tab to render with a balance, then let
    // Electrum sync catch up so the balance/tx list aren't stuck at zero.
    let balanceExists = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'sats'")).firstMatch
    XCTAssertTrue(balanceExists.waitForExistence(timeout: 15), "Main screen should appear after wallet creation")
    sleep(12)

    // MARK: 03 - Transactions (balance hero + tx list)
    snapshot("03-Transactions")

    // MARK: 04 - Wallet Picker (overlay on transactions screen)
    let walletPicker = app.buttons["walletPicker"].firstMatch
    if walletPicker.waitForExistence(timeout: 3) {
      walletPicker.tap()
      let walletsTitle = app.staticTexts["Wallets"]
      XCTAssertTrue(walletsTitle.waitForExistence(timeout: 3), "Wallet picker overlay should appear")
      sleep(1)
      snapshot("04-WalletPicker")
      // Dismiss by tapping the wallet picker button again
      walletPicker.tap()
      sleep(1)
    }

    // MARK: 05 - Transaction Detail (tap first received transaction)
    let firstTxCell = app.cells.firstMatch
    if firstTxCell.waitForExistence(timeout: 5) {
      firstTxCell.tap()
      let receivedLabel = app.staticTexts["Received"]
      let sentLabel = app.staticTexts["Sent"]
      let detailAppeared = receivedLabel.waitForExistence(timeout: 5) || sentLabel.waitForExistence(timeout: 2)
      XCTAssertTrue(detailAppeared, "Transaction detail should show Received or Sent label")
      sleep(1)
      snapshot("05-TransactionDetail")
      // Go back to transaction list
      app.navigationBars.buttons.element(boundBy: 0).tap()
      sleep(1)
    }

    // MARK: 06 - Dashboard sheet (via "..." overflow menu)
    let walletMenu = app.buttons["walletMenu"].firstMatch
    if walletMenu.waitForExistence(timeout: 3) {
      walletMenu.tap()
      let dashboardMenuItem = app.buttons["Dashboard"]
      if dashboardMenuItem.waitForExistence(timeout: 3) {
        dashboardMenuItem.tap()
        // Give the sheet a beat to animate in.
        sleep(1)
        snapshot("06-Dashboard")
        // Dismiss the sheet by swiping the window down.
        app.windows.firstMatch.swipeDown(velocity: .fast)
      }
    }

    // MARK: 07 - Receive
    let receiveTab = app.tabBars.buttons["Receive"]
    XCTAssertTrue(receiveTab.waitForExistence(timeout: 5), "Receive tab should exist")
    receiveTab.tap()
    let viewAllAddresses = app.buttons["View All Addresses"]
    XCTAssertTrue(viewAllAddresses.waitForExistence(timeout: 10), "View All Addresses link should appear")
    snapshot("07-Receive")

    // MARK: 08 - Addresses
    viewAllAddresses.tap()
    let addressesTitle = app.navigationBars["Addresses"]
    XCTAssertTrue(addressesTitle.waitForExistence(timeout: 10), "Addresses screen should appear")
    snapshot("08-Addresses")

    // MARK: 09 - Address Detail (tap first address)
    let firstAddressCell = app.cells.firstMatch
    if firstAddressCell.waitForExistence(timeout: 5) {
      firstAddressCell.tap()
      let copyAddressButton = app.buttons["Copy Address"]
      XCTAssertTrue(copyAddressButton.waitForExistence(timeout: 5), "Address detail should show Copy Address button")
      snapshot("09-AddressDetail")
      // Go back to address list
      app.navigationBars.buttons.element(boundBy: 0).tap()
      sleep(1)
    }

    // MARK: 10 - Send (lands on recipients step)
    let sendTab = app.tabBars.buttons["Send"]
    XCTAssertTrue(sendTab.waitForExistence(timeout: 5), "Send tab should exist")
    sendTab.tap()
    // SendFlowView headline is a static text "Send" — wait for it to avoid
    // racing the tab animation.
    _ = app.staticTexts["Send"].waitForExistence(timeout: 5)
    snapshot("10-Send")

    // MARK: 11 - UTXOs
    let utxosTab = app.tabBars.buttons["UTXOs"]
    XCTAssertTrue(utxosTab.waitForExistence(timeout: 5), "UTXOs tab should exist")
    utxosTab.tap()
    let utxosHeader = app.staticTexts["UTXOs"]
    XCTAssertTrue(utxosHeader.waitForExistence(timeout: 5), "UTXOs header should appear")
    sleep(1)
    snapshot("11-UTXOs")

    // MARK: 12 - UTXO Detail (tap first UTXO)
    let firstUTXOCell = app.cells.firstMatch
    if firstUTXOCell.waitForExistence(timeout: 5) {
      firstUTXOCell.tap()
      let utxoDetailTitle = app.navigationBars["UTXO Detail"]
      XCTAssertTrue(utxoDetailTitle.waitForExistence(timeout: 5), "UTXO Detail screen should appear")
      snapshot("12-UTXODetail")
      // Go back to UTXO list
      app.navigationBars.buttons.element(boundBy: 0).tap()
      sleep(1)
    }

    // MARK: 13 - Settings
    let settingsTab = app.tabBars.buttons["Settings"]
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 5), "Settings tab should exist")
    settingsTab.tap()
    sleep(1)
    snapshot("13-Settings")

    // MARK: Navigate to Transactions and open wallet picker

    let transactionsTab = app.tabBars.buttons["Transactions"]
    XCTAssertTrue(transactionsTab.waitForExistence(timeout: 5), "Transactions tab should exist")
    transactionsTab.tap()
    sleep(1)

    let walletPickerBtn = app.buttons["walletPicker"].firstMatch
    XCTAssertTrue(walletPickerBtn.waitForExistence(timeout: 3), "Wallet picker button should exist")
    walletPickerBtn.tap()
    let walletsTitleAdd = app.staticTexts["Wallets"]
    XCTAssertTrue(walletsTitleAdd.waitForExistence(timeout: 3), "Wallet picker overlay should appear")
    sleep(1)

    let addWalletBtn = app.buttons["Add"]
    XCTAssertTrue(addWalletBtn.waitForExistence(timeout: 3), "Add button should exist in wallet picker")
    addWalletBtn.tap()

    // Setup Wizard sheet opens — Welcome step
    let getStartedNew = app.buttons["Get Started"]
    XCTAssertTrue(getStartedNew.waitForExistence(timeout: 5), "Welcome screen should show 'Get Started' button")
    getStartedNew.tap()

    // Creation choice — tap "Create New Wallet"
    let createNewCard = app.staticTexts["Create New Wallet"]
    XCTAssertTrue(createNewCard.waitForExistence(timeout: 3), "Creation choice should show 'Create New Wallet' option")
    createNewCard.tap()

    // MARK: 14 - Multisig Configuration (Testnet4 default)
    let multisigTitle = app.staticTexts["Multisig Configuration"]
    XCTAssertTrue(multisigTitle.waitForExistence(timeout: 5), "Multisig Configuration screen should appear")
    sleep(1)
    snapshot("14-MultisigConfig-Testnet4")

    // Switch to Mainnet
    let mainnetSegBtn = app.segmentedControls.firstMatch.buttons["Mainnet"]
    XCTAssertTrue(mainnetSegBtn.waitForExistence(timeout: 3), "Mainnet segment button should exist")
    mainnetSegBtn.tap()
    sleep(1)

    // MARK: 15 - Multisig Configuration (Mainnet)
    snapshot("15-MultisigConfig-Mainnet")

    // Switch back to Testnet4
    let testnet4SegBtn = app.segmentedControls.firstMatch.buttons["Testnet4"]
    XCTAssertTrue(testnet4SegBtn.waitForExistence(timeout: 3), "Testnet4 segment button should exist")
    testnet4SegBtn.tap()
    sleep(1)

    // Advance to cosigner import
    let multisigNextBtn = app.buttons["Next"]
    XCTAssertTrue(multisigNextBtn.waitForExistence(timeout: 3), "Next button should exist on multisig config screen")
    multisigNextBtn.tap()

    // MARK: 16 - Empty Cosigner Import Screen
    let cosignerImportTitle = app.staticTexts["Import Cosigners"]
    XCTAssertTrue(cosignerImportTitle.waitForExistence(timeout: 5), "Import Cosigners screen should appear")
    sleep(1)
    snapshot("16-CosignerImport-Empty")

    // MARK: Fill Cosigner 1
    // Type fingerprint into TextField, press Return to dismiss its keyboard.
    // Then type xpub directly into the TextEditor (avoids the system clipboard
    // permission prompt), and dismiss via swipeDown (scrollDismissesKeyboard).
    // Do NOT press Return in the TextEditor — it inserts a newline that would
    // corrupt the xpub and fail BDK descriptor parsing.
    let fpField1 = app.textFields["e.g. 73c5da0a"]
    XCTAssertTrue(fpField1.waitForExistence(timeout: 3), "Fingerprint field should exist")
    fpField1.tap()
    fpField1.typeText("07d25f0c")
    app.keyboards.buttons["Return"].tap()

    let xpubEditor1 = app.textViews.firstMatch
    XCTAssertTrue(xpubEditor1.waitForExistence(timeout: 3), "Xpub text editor should exist")
    xpubEditor1.tap()
    xpubEditor1.typeText("tpubDE2gU1F6b1GXDg2bFjeq6RUnBmAe2moTNG7x47Cga3VnVnm7EJWLdJE73ZL2MEwKTc2dLNeSudXUjexm2xJ5qboosbnEb1SEiGyJtJcqqZK")
    app.swipeDown()
    sleep(1)

    // MARK: 17 - Cosigner 1 Filled (no keyboard)
    snapshot("17-CosignerImport-Cosigner1")

    let nextCosignerBtn1 = app.buttons["Next Cosigner"]
    XCTAssertTrue(nextCosignerBtn1.waitForExistence(timeout: 3), "Next Cosigner button should exist")
    nextCosignerBtn1.tap()
    sleep(1)

    // MARK: Fill Cosigner 2
    let fpField2 = app.textFields["e.g. 73c5da0a"]
    XCTAssertTrue(fpField2.waitForExistence(timeout: 3), "Fingerprint field should exist for cosigner 2")
    fpField2.tap()
    fpField2.typeText("d73869a4")
    app.keyboards.buttons["Return"].tap()

    let xpubEditor2 = app.textViews.firstMatch
    XCTAssertTrue(xpubEditor2.waitForExistence(timeout: 3), "Xpub text editor should exist for cosigner 2")
    xpubEditor2.tap()
    xpubEditor2.typeText("tpubDET5GnMK8Zr7UH63ni72etKd7ZYxVq8NvtSneNBfEDJ7YtnSHUmiPCaBYXzCdR6ZBKWvBMXT3urCVp7sLmG6z8VTpdFRJuW4VL7xjHdLFpY")
    app.swipeDown()
    sleep(1)

    let nextCosignerBtn2 = app.buttons["Next Cosigner"]
    XCTAssertTrue(nextCosignerBtn2.waitForExistence(timeout: 3), "Next Cosigner button should exist for cosigner 2")
    nextCosignerBtn2.tap()
    sleep(1)

    // MARK: Fill Cosigner 3
    let fpField3 = app.textFields["e.g. 73c5da0a"]
    XCTAssertTrue(fpField3.waitForExistence(timeout: 3), "Fingerprint field should exist for cosigner 3")
    fpField3.tap()
    fpField3.typeText("e3870581")
    app.keyboards.buttons["Return"].tap()

    let xpubEditor3 = app.textViews.firstMatch
    XCTAssertTrue(xpubEditor3.waitForExistence(timeout: 3), "Xpub text editor should exist for cosigner 3")
    xpubEditor3.tap()
    xpubEditor3.typeText("tpubDF3GwUrMb5WkigsDUpUWUADH55G3Ez771QujmFqeyrNEPD7onkqTwCsCEjNRbSrbD9VYKDfMHfg7bajem5aEX7CyMp2q5fvQzacy75bUesQ")
    app.swipeDown()
    sleep(1)

    // MARK: 18 - Cosigner 3 Filled (no keyboard)
    snapshot("18-CosignerImport-Cosigner3")

    let continueBtn = app.buttons["Continue"]
    XCTAssertTrue(continueBtn.waitForExistence(timeout: 3), "Continue button should exist")
    continueBtn.tap()

    // MARK: 19 - Wallet Name
    let nameWalletTitle = app.staticTexts["Name Your Wallet"]
    XCTAssertTrue(nameWalletTitle.waitForExistence(timeout: 10), "Wallet name screen should appear")
    let newWalletNameField = app.textFields["My Wallet"]
    XCTAssertTrue(newWalletNameField.waitForExistence(timeout: 3), "Wallet name text field should exist")
    newWalletNameField.tap()
    newWalletNameField.typeText("My New Wallet")
    app.swipeDown()
    sleep(1)
    snapshot("19-WalletName")

    let walletNameNextBtn = app.buttons["Next"]
    XCTAssertTrue(walletNameNextBtn.waitForExistence(timeout: 3), "Next button should exist on wallet name screen")
    walletNameNextBtn.tap()

    // MARK: 20 - Verify Wallet (top — summary + cosigners)
    let verifyWalletTitle = app.staticTexts["Verify Wallet"]
    XCTAssertTrue(verifyWalletTitle.waitForExistence(timeout: 30), "Verify Wallet screen should appear")
    sleep(2)
    snapshot("20-VerifyWallet-Top")

    // Scroll up a controlled amount to land at the "Back Up Your Descriptor"
    // section. swipeUp(velocity: .slow) overshoots by ~60pt, so use a
    // fixed-distance coordinate drag instead.
    let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
    let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
    dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
    sleep(1)

    // MARK: 21 - Verify Wallet (backup section)
    snapshot("21-VerifyWallet-Backup")

    // Scroll to bring "Verify Receive Address" section to the top
    app.swipeUp()
    sleep(1)

    // MARK: 22 - Verify Wallet (receive address section)
    snapshot("22-VerifyWallet-Verify")

    // Tap "Create Wallet"
    let createWalletFinalBtn = app.buttons["Create Wallet"]
    XCTAssertTrue(createWalletFinalBtn.waitForExistence(timeout: 5), "Create Wallet button should exist")
    createWalletFinalBtn.tap()

    // MARK: 23 - New Wallet syncing
    // Capture the transaction screen ~3 seconds into the sync (sheet animates
    // away in ~1s, then sync starts — total sleep of 4s lands mid-sync).
    snapshot("23-NewWalletLoading")
  }
}
