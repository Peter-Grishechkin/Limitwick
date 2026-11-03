# Publishing updates


Sparkle 2.10.1 is downloaded from its official GitHub release and checked against the SHA-256 in `build.sh`. The appcast is `appcast.xml` on the repository's main branch. Each future release must be signed with the `codex-bar-updates` Sparkle key in the macOS login keychain. Keep a secure backup of the key: ad hoc signed builds cannot rely on Developer ID key rotation if it is lost. Never commit the private key.

Build the release app with `CODEXBAR_BUILD_CONFIGURATION=release ./build.sh` and test that exact app. The default build is a separate development app and must not be published. Create a ZIP preserving framework symlinks with `ditto -c -k --sequesterRsrc --keepParent`, publish that exact ZIP in the GitHub release with a non-empty Markdown `## Changes` section, then run `./scripts/prepare-appcast.sh VERSION PATH_TO_RELEASE_ZIP`. The script copies that section into the update prompt. Publish the updated appcast on main after the release is available. Verify the published feed and test installation from a previous Sparkle-enabled version. Version 1.4.2 has no Sparkle updater, so users must install the first Sparkle-enabled version manually.
