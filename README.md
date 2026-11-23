# WarFront iOS WebView prototype

An offline iOS wrapper of the web assets bundled in the provided WarFront Android project. Uses SwiftUI + WKWebView and an on-device **loopback-only HTTP server** so absolute asset paths and web workers can use an HTTP origin. No conversion to C++.

## Build from Samsung S23 / Termux

1. Install Termux and `pkg install git`. Set up a GitHub repository (private is recommended if assets are not licensed for redistribution).
2. Upload or `git push` the contents of this directory **including `.github/workflows/build-ios.yml` and `WarFrontIOS/Web/`**. If GitHub refuses large files, use Git LFS or upload a source ZIP to a cloud Mac build service instead.
3. On GitHub, open **Actions > Build WarFront iOS (unsigned) > Run workflow**.
4. When completed, download the `WarFront-iOS-unsigned-IPA` artifact. It contains an **unsigned** `.ipa` and **cannot be installed directly** on iPhone without valid signing/provisioning.
5. For a signed installation, use your own Apple developer signing credentials and provisioning profile in a secure macOS build/signing workflow. Never commit certificates/passwords to a repository.

## Important limitations

- This project has **not** been built with Xcode or tested on iOS in this environment.
- WarFront's original bundle may use browser features unsupported by the target iOS WebKit (WebGL features, workers, audio, fullscreen, file handling). Compatibility must be tested on a real iPhone.
- Game assets were extracted without editing the original gameplay JS. The original `index.html` includes existing Android-oriented optimizations and absolute paths; these may require iOS-specific adjustments.
- Server listens only on `127.0.0.1` and serves static files; it is not an internet-facing service.
- The source bundle is ~162 MB uncompressed. GitHub runner and repository storage limits may apply.
- No Apple signing keys are included. Use only assets you have rights to distribute.
