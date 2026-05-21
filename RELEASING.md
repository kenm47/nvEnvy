# Releasing nvEnvy

## Build Configurations

- **Debug**: Default for development. Includes debug symbols.
- **Release**: Optimized build for distribution.

## Building a Release Archive

```bash
cd nvEnvy
xcodegen generate
xcodebuild -project nvEnvy.xcodeproj -scheme nvEnvy -configuration Release archive \
  -archivePath build/nvEnvy.xcarchive
```

## Universal Binary

The project is configured with `ARCHS = $(ARCHS_STANDARD)`, which builds for both arm64 (Apple Silicon) and x86_64 (Intel) in Release mode.

## Code Signing

Sign with a Developer ID certificate for distribution outside the Mac App Store:

```bash
xcodebuild -project nvEnvy.xcodeproj -scheme nvEnvy -configuration Release archive \
  -archivePath build/nvEnvy.xcarchive \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

## Notarization

After archiving, export the app and submit for notarization:

```bash
# Export from archive
xcodebuild -exportArchive -archivePath build/nvEnvy.xcarchive \
  -exportPath build/export -exportOptionsPlist ExportOptions.plist

# Submit for notarization
xcrun notarytool submit build/export/nvEnvy.app.zip \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# Staple the notarization ticket
xcrun stapler staple build/export/nvEnvy.app
```

## DMG Creation

Create a distributable DMG:

```bash
# Using hdiutil
hdiutil create -volname "nvEnvy" -srcfolder build/export/nvEnvy.app \
  -ov -format UDZO build/nvEnvy-1.0.0.dmg

# Or using create-dmg for a styled DMG
create-dmg \
  --volname "nvEnvy" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "nvEnvy.app" 150 190 \
  --app-drop-link 450 190 \
  build/nvEnvy-1.0.0.dmg build/export/nvEnvy.app
```

## Sparkle Auto-Update

The direct-download (DMG) build of nvEnvy includes Sparkle for auto-updates. The appcast URL is configured as `https://nvenvy.app/appcast.xml` in Info.plist (`SUFeedURL`). The Mac App Store build (scheme `nvEnvy-MAS`) excludes Sparkle entirely; MAS updates flow through the App Store.

To publish an update:
1. Build and sign the new version
2. Generate the appcast entry using Sparkle's `generate_appcast` tool
3. Upload the DMG and updated `appcast.xml` to the server

## Version Numbering

- `CFBundleShortVersionString` (MARKETING_VERSION): Semantic version (e.g., "1.0.0")
- `CFBundleVersion` (CURRENT_PROJECT_VERSION): Build number (increment with each build)

Update both in `nvEnvy/project.yml` before each release.
