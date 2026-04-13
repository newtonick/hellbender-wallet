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

    // MARK: 02 - Transactions (balance hero + tx list)
    snapshot("02-Transactions")

    // MARK: 03 - Wallet Picker (overlay on transactions screen)
    let walletPicker = app.buttons["walletPicker"].firstMatch
    if walletPicker.waitForExistence(timeout: 3) {
      walletPicker.tap()
      let walletsTitle = app.staticTexts["Wallets"]
      XCTAssertTrue(walletsTitle.waitForExistence(timeout: 3), "Wallet picker overlay should appear")
      sleep(1)
      snapshot("03-WalletPicker")
      // Dismiss by tapping the wallet picker button again
      walletPicker.tap()
      sleep(1)
    }

    // MARK: 04 - Transaction Detail (tap first received transaction)
    let firstTxCell = app.cells.firstMatch
    if firstTxCell.waitForExistence(timeout: 5) {
      firstTxCell.tap()
      let receivedLabel = app.staticTexts["Received"]
      let sentLabel = app.staticTexts["Sent"]
      let detailAppeared = receivedLabel.waitForExistence(timeout: 5) || sentLabel.waitForExistence(timeout: 2)
      XCTAssertTrue(detailAppeared, "Transaction detail should show Received or Sent label")
      sleep(1)
      snapshot("04-TransactionDetail")
      // Go back to transaction list
      app.navigationBars.buttons.element(boundBy: 0).tap()
      sleep(1)
    }

    // MARK: 05 - Dashboard sheet (via "..." overflow menu)
    let walletMenu = app.buttons["walletMenu"].firstMatch
    if walletMenu.waitForExistence(timeout: 3) {
      walletMenu.tap()
      let dashboardMenuItem = app.buttons["Dashboard"]
      if dashboardMenuItem.waitForExistence(timeout: 3) {
        dashboardMenuItem.tap()
        // Give the sheet a beat to animate in.
        sleep(1)
        snapshot("05-Dashboard")
        // Dismiss the sheet by swiping the window down.
        app.windows.firstMatch.swipeDown(velocity: .fast)
      }
    }

    // MARK: 06 - Receive
    let receiveTab = app.tabBars.buttons["Receive"]
    XCTAssertTrue(receiveTab.waitForExistence(timeout: 5), "Receive tab should exist")
    receiveTab.tap()
    let viewAllAddresses = app.buttons["View All Addresses"]
    XCTAssertTrue(viewAllAddresses.waitForExistence(timeout: 10), "View All Addresses link should appear")
    snapshot("06-Receive")

    // MARK: 07 - Addresses
    viewAllAddresses.tap()
    let addressesTitle = app.navigationBars["Addresses"]
    XCTAssertTrue(addressesTitle.waitForExistence(timeout: 10), "Addresses screen should appear")
    snapshot("07-Addresses")

    // MARK: 08 - Address Detail (tap first address)
    let firstAddressCell = app.cells.firstMatch
    if firstAddressCell.waitForExistence(timeout: 5) {
      firstAddressCell.tap()
      let copyAddressButton = app.buttons["Copy Address"]
      XCTAssertTrue(copyAddressButton.waitForExistence(timeout: 5), "Address detail should show Copy Address button")
      snapshot("08-AddressDetail")
      // Go back to address list
      app.navigationBars.buttons.element(boundBy: 0).tap()
      sleep(1)
    }

    // MARK: 09 - Send (lands on recipients step)
    let sendTab = app.tabBars.buttons["Send"]
    XCTAssertTrue(sendTab.waitForExistence(timeout: 5), "Send tab should exist")
    sendTab.tap()
    // SendFlowView headline is a static text "Send" — wait for it to avoid
    // racing the tab animation.
    _ = app.staticTexts["Send"].waitForExistence(timeout: 5)
    snapshot("09-Send")

    // MARK: 10 - UTXOs
    let utxosTab = app.tabBars.buttons["UTXOs"]
    XCTAssertTrue(utxosTab.waitForExistence(timeout: 5), "UTXOs tab should exist")
    utxosTab.tap()
    let utxosHeader = app.staticTexts["UTXOs"]
    XCTAssertTrue(utxosHeader.waitForExistence(timeout: 5), "UTXOs header should appear")
    sleep(1)
    snapshot("10-UTXOs")

    // MARK: 11 - UTXO Detail (tap first UTXO)
    let firstUTXOCell = app.cells.firstMatch
    if firstUTXOCell.waitForExistence(timeout: 5) {
      firstUTXOCell.tap()
      let utxoDetailTitle = app.navigationBars["UTXO Detail"]
      XCTAssertTrue(utxoDetailTitle.waitForExistence(timeout: 5), "UTXO Detail screen should appear")
      snapshot("11-UTXODetail")
      // Go back to UTXO list
      app.navigationBars.buttons.element(boundBy: 0).tap()
      sleep(1)
    }

    // MARK: 12 - Settings
    let settingsTab = app.tabBars.buttons["Settings"]
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 5), "Settings tab should exist")
    settingsTab.tap()
    sleep(1)
    snapshot("12-Settings")
  }
}
