# Privacy Policy

**Effective: 2026**

nvEnvy is a note-taking app for macOS. It is designed to keep your notes on
your own machine and to send nothing about you anywhere.

## What we collect

**Nothing.** nvEnvy does not collect, transmit, sell, or share any personal
data, usage analytics, telemetry, crash reports, advertising identifiers, or
device information.

## Where your notes live

- Your notes are stored as plain Markdown files in a folder you choose on your
  Mac.
- If you place that folder inside iCloud Drive, those files are synced between
  your devices by **Apple's iCloud**, under **your own iCloud account**.
  nvEnvy does not operate a sync server and has no access to your iCloud data.
- A small amount of per-app state (window position, search bookmarks, recently
  opened notes) is stored in `~/Library/Application Support/nvEnvy/` and in
  the macOS user-defaults database. This data never leaves your Mac.
- The app also uses Apple's iCloud Key-Value Store to sync a few small
  preferences (such as bookmarks) between your devices. This too is end-to-end
  under your Apple ID and never reaches the developer.

## Network connections

- **Mac App Store build:** the app makes no outbound network connections of
  its own.
- **Direct-download build (DMG):** the app uses Sparkle to check
  `https://nvenvy.app/appcast.xml` for software updates. This is a static XML
  file; the request is unauthenticated and contains only what your operating
  system sends with any URL request (HTTP user agent, IP at the network
  layer). No usage information is included.

## Third parties

nvEnvy does not embed advertising SDKs, analytics SDKs, crash reporters, or
any other third-party data collectors. Open-source dependencies used at build
time (Sparkle, KeyboardShortcuts, Yams, swift-markdown) operate entirely
within the app and do not transmit data.

## Contact

If you have questions about this policy, please open an issue at
<https://github.com/kenm47/nvEnvy/issues>.

The canonical version of this policy is hosted at
<https://nvenvy.app/privacy>.
