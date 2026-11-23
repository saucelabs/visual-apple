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

let visual = try VisualClient(options: VisualBuildOptions(name: "My build"))
try await visual.sauceVisualCheck("Home screen")
```

## License

[Apache-2.0](LICENSE).
