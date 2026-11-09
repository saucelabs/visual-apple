# Sauce Labs Visual for Apple platforms

Sauce Labs Visual for XCUITest adds visual testing to your UI tests on iOS/iPadOS 15+, tvOS 15+, and macOS 14+, from Swift or Objective-C.

## Installation

Add `SauceVisual` to your **UI test target only**, not to the app.

### Swift Package Manager

In Xcode, choose **File → Add Package Dependencies…**, enter `https://github.com/saucelabs/visual-apple`, and add the `SauceVisual` product to the UI test target. Or in a `Package.swift`:

```swift
.package(url: "https://github.com/saucelabs/visual-apple", from: "0.1.0")
```

`SauceVisual` is a dynamic framework, so the UI test target must embed it. In **Build Phases**, add a **Copy Files** phase with **Destination: Frameworks**, add `SauceVisual` to it, and check **Code Sign On Copy**. Without it, tests on a physical device fail with `Library not loaded: @rpath/SauceVisual.framework/SauceVisual`.

### XCFramework

Build it with `Scripts/build-xcframework.sh`, add `SauceVisual.xcframework` to the UI test target, and choose **Embed & Sign**.

## Configuration

| Variable | Purpose |
|---|---|
| `SAUCE_USERNAME`, `SAUCE_ACCESS_KEY` | Sauce Labs credentials (required) |
| `SAUCE_REGION` | `us-west-1` (default), `us-east-4`, `eu-central-1`, `asia-south-2` |
| `SAUCE_VISUAL_BUILD_NAME`, `SAUCE_VISUAL_PROJECT`, `SAUCE_VISUAL_BRANCH`, `SAUCE_VISUAL_DEFAULT_BRANCH` | Build attributes |
| `SAUCE_VISUAL_CUSTOM_ID`, `SAUCE_VISUAL_BUILD_ID` | Reuse a running build |
| `SAUCE_VISUAL_TAGS` | Comma-separated build tags |

Values passed in code take precedence. Tests don't inherit your shell, so pass variables with the `TEST_RUNNER_` prefix, or set them in the scheme's Test action:

```bash
TEST_RUNNER_SAUCE_USERNAME="$SAUCE_USERNAME" TEST_RUNNER_SAUCE_ACCESS_KEY="$SAUCE_ACCESS_KEY" \
  xcodebuild test -scheme MyAppUITests -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Usage

```swift
import SauceVisual

let visual = try VisualClient(options: VisualBuildOptions(name: "Checkout", project: "iOS app"))

// In a UI test, after driving the app to the screen you want to compare:
try await visual.sauceVisualCheck("Checkout page")

// With options
try await visual.sauceVisualCheck("Products", options: VisualCheckOptions(
    clipElement: app.otherElements["cart"],
    ignoreRegions: [CGRect(x: 0, y: 0, width: 402, height: 62)],   // points
    ignoreElements: [app.staticTexts["timestamp"]],
    captureDom: true
))
```

The SDK creates the build on the first check and finishes it when the tests end. Test and suite names are taken from the running test.

| Option | Purpose |
|---|---|
| `clipElement` | Snapshot only this element |
| `ignoreRegions`, `ignoreElements` | Leave areas or elements out of the comparison |
| `regions` | Ignore or detect changes in an area with its own rules |
| `diffingMethod`, `diffingOptions`, `diffingMethodSensitivity`, `diffingMethodTolerance` | How the snapshot is compared |
| `baselineOverride` | Compare against another snapshot's baseline, for example another OS version |
| `captureDom` | Also upload the element tree, so the dashboard shows which element changed |
| `fullPage` | Scroll an element and stitch its content into one image (not on tvOS) |
| `testName`, `suiteName` | Override the names taken from the running test |

**Sharing a build between workers.** Give every worker the same `customId` and a `finishDelay`. The service finishes the build that many seconds after the last worker is done:

```swift
let visual = try VisualClient(options: VisualBuildOptions(customId: ciPipelineId, finishDelay: 120))
```

A build named by `buildId`, or by `customId` without `finishDelay`, is left open for you to finish, for example with `finish()`.

### Objective-C

```objc
@import SauceVisual;

NSError *error = nil;
SLVBuildOptions *options = [[SLVBuildOptions alloc] initWithName:@"Checkout" project:@"iOS app"
    branch:nil defaultBranch:nil customId:nil buildId:nil finishDelay:nil tags:nil];
SLVClient *visual = [[SLVClient alloc] initWithOptions:options error:&error];

[visual sauceVisualCheckWithName:@"Checkout page" completion:^(SLVSnapshot *snapshot, NSError *failure) {
    if (failure != nil) { NSLog(@"Check failed: %@", failure.localizedDescription); }
}];
```

With the XCFramework, use `#import <SauceVisual/SauceVisual-Swift.h>`. Pass `SLVCheckOptions` with `sauceVisualCheckWithName:options:completion:` for the check options, and `initWithUsername:accessKey:region:options:error:` to pass credentials in code.

## Troubleshooting

- **`Library not loaded` on a device:** the UI test target doesn't embed `SauceVisual`. See [Swift Package Manager](#swift-package-manager).
- **A test run from Xcode hangs on a device at `Wait for … to idle`:** the app is signed for distribution, so the debugger can't attach. Sign the app for development in the configuration the Test action builds, or turn off **Debug executable** in the scheme's Test action.

## Development

```bash
xcrun swift test                                  # unit tests
Scripts/test.sh source iphone                     # integration tests: iphone, ipad, tvos, macos
Scripts/build-xcframework.sh && Scripts/test.sh binary iphone
```

Integration tests create real builds and need `SAUCE_USERNAME` and `SAUCE_ACCESS_KEY`.

## License

[Apache-2.0](LICENSE).
