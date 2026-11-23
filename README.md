# Sauce Labs Visual for XCUITest

Sauce Labs Visual for XCUITest exposes Sauce Labs Visual Testing for your iOS, iPadOS, tvOS, and macOS apps.

## Installation & Usage

<!-- TODO: once the Sauce Docs page is published, replace this section with:
View installation and usage instructions on the [Sauce Docs website](https://docs.saucelabs.com/visual-testing/integrations/xcuitest/).
-->

Choose one installation method and link and embed the SDK in your **XCUITest UI test target**.

### Swift Package Manager

1. In Xcode, choose **File → Add Package Dependencies…** and enter `https://github.com/saucelabs/visual-apple`.
2. Select a released version and add the `SauceVisual` product to your UI test target.
3. In the UI test target’s **Build Phases**, add or reuse a **Copy Files** phase with **Destination** set to **Frameworks** and **Subpath** left empty. Add `SauceVisual` to the phase and enable **Code Sign On Copy** so the test runner can load the framework on physical devices.

### XCFramework

1. Open [GitHub Releases](https://github.com/saucelabs/visual-apple/releases), choose a release that lists a `SauceVisual-*.xcframework.zip` asset, and download and unzip it. For versions without a binary asset, use Swift Package Manager.
2. Add the extracted `SauceVisual.xcframework` to your project and link it in the UI test target. If Xcode offers an embedding option, choose **Embed & Sign**. Otherwise, add it to the test target’s **Link Binary With Libraries** and to a **Copy Files** phase with destination **Frameworks** and **Code Sign On Copy** enabled.

The archive includes the matching debug symbols (dSYMs). The release includes the license alongside the archive.

### Run a visual check

Set `SAUCE_USERNAME` and `SAUCE_ACCESS_KEY` for the test run, then in a UI test:

```swift
import SauceVisual

let visual = try VisualClient(options: VisualBuildOptions(name: "My build"))
try await visual.sauceVisualCheck("Home screen")
```

## License

[Apache-2.0](LICENSE).
