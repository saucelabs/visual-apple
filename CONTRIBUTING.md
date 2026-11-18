# Contributing

Thanks for helping improve Sauce Labs Visual for XCUITest. Please follow our [Code of Conduct](CODE_OF_CONDUCT.md).

To report a security vulnerability, don't open an issue. Follow [SECURITY.md](SECURITY.md) instead.

## Before you start

For anything bigger than a small fix, open an issue first so we can agree on the approach.

## Development

You need a Mac with Xcode 26.

```sh
swift build
swift test
```

CI also builds with strict concurrency and treats warnings as errors, so check this before you push:

```sh
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

The XCFramework is built from `SauceVisual.xcodeproj`, which lists its source files by hand. If you add, move, or remove a file in `Sources/`, update the project too. `Scripts/check-xcodeproj-sources.sh` checks this.

## Integration tests

The integration tests run on a simulator and create real Sauce Visual builds, so they need `SAUCE_USERNAME` and `SAUCE_ACCESS_KEY`:

```sh
Scripts/test.sh source iphone    # or ipad, tvos, macos
```

To test the XCFramework:

```sh
Scripts/build-xcframework.sh
Scripts/test.sh binary iphone    # or ipad, tvos, macos
```

Pull requests from forks don't get these credentials in CI, so their integration tests fail. A maintainer runs them before merging.

## Pull requests

- Keep each pull request to one change, and add tests for it.
- Describe what changed and how you tested it. The pull request template has the sections.
- A member of the Visual team must approve the pull request, and CI must pass.

Maintainers make releases. Don't change the version in `Configuration/SDK.xcconfig` or `Sources/SauceVisual/API/GraphQLTransport.swift`.

## License

By contributing, you agree that your contributions are licensed under the [Apache-2.0 License](LICENSE).
