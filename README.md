# Sauce Labs Visual for XCUITest

Sauce Labs Visual for XCUITest exposes Sauce Labs Visual Testing for your iOS, iPadOS, tvOS, and macOS apps.

## Installation & Usage

<!-- TODO: once the Sauce Docs page is published, replace this section with:
View installation and usage instructions on the [Sauce Docs website](https://docs.saucelabs.com/visual-testing/integrations/xcuitest/).
-->

In Xcode, choose **File → Add Package Dependencies…**, enter `https://github.com/saucelabs/visual-apple`, and add the `SauceVisual` product to your UI test target.

Set `SAUCE_USERNAME` and `SAUCE_ACCESS_KEY` for the test run, then in a UI test:

```swift
import SauceVisual

let visual = try await VisualClient(options: VisualBuildOptions(name: "My build"))
try await visual.sauceVisualCheck("Home screen")
```

## Building

Sauce Visual XCUITest SDK uses [Swift Package Manager](https://www.swift.org/documentation/package-manager/) and Xcode 26.

```sh
swift build
```

To build `SauceVisual.xcframework`:

```sh
Scripts/build-xcframework.sh
```

## Running the tests

To run the unit tests:

```sh
swift test
```

The integration tests run on a simulator and create real builds. Make sure that `SAUCE_USERNAME` and `SAUCE_ACCESS_KEY` environment variables are in place before running them:

```sh
Scripts/test.sh source iphone    # or ipad, tvos, macos
```

## License

[Apache-2.0](LICENSE).
