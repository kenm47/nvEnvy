# Contributing to nvEnvy

Thanks for your interest in nvEnvy. This is a small, opinionated project, so contributions are best discussed in an issue before you sink time into a PR.

## Building

You'll need:

- macOS 14.0 (Sonoma) or newer
- Xcode 15+ (Swift 5.9)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

To build the macOS app:

```bash
cd nvEnvy
xcodegen generate
open nvEnvy.xcodeproj
```

There are two app schemes:

- **`nvEnvy`** — direct-download build. Links Sparkle for in-app updates.
- **`nvEnvy-MAS`** — Mac App Store build. Sparkle is excluded; updates flow through the App Store.

For day-to-day development, use the `nvEnvy` scheme.

## Tests

The data layer (`NvEnvyCore`) is a Swift Package with full unit-test coverage:

```bash
cd NvEnvyCore
swift test
```

All tests should pass on `main`. PRs that break tests will not be merged.

## Pull requests

- Open an issue first for anything non-trivial. Drive-by feature PRs without prior discussion are likely to be closed.
- Keep changes focused: one PR, one logical change.
- Match the existing code style. Run the test suite before pushing.
- Bug fixes should include a regression test where practical.

## Issues

- Search before filing — odds are good your bug or idea has been raised.
- For bugs, include macOS version, nvEnvy build, and reproduction steps.
- Triage is best-effort — please be patient.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
