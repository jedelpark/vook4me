#!/bin/bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
    echo 'UI execution is restricted to an isolated GitHub-hosted VM.' >&2
    exit 1
}
CI_SMOKE_ROOT="$RUNNER_TEMP/vook-release-smoke"
mkdir -p "$CI_SMOKE_ROOT/download" "$CI_SMOKE_ROOT/results" "$CI_SMOKE_ROOT/mount"
sw_vers
uname -m
xcodebuild -version
gh release download v1.8.4 --repo jedelpark/vook4me --pattern Vook4Me-1.8.4.dmg --dir "$CI_SMOKE_ROOT/download"
unset GH_TOKEN GITHUB_TOKEN
echo 'b0b0b4c3f470616ab10aaa1213c35457e750ba66b28f76af2c8a069693f745ca  Vook4Me-1.8.4.dmg' > "$CI_SMOKE_ROOT/download/SHA256SUMS"
(cd "$CI_SMOKE_ROOT/download" && shasum -a 256 -c SHA256SUMS)
hdiutil attach -readonly -nobrowse -mountpoint "$CI_SMOKE_ROOT/mount" "$CI_SMOKE_ROOT/download/Vook4Me-1.8.4.dmg"
trap 'hdiutil detach "$CI_SMOKE_ROOT/mount" >/dev/null 2>&1 || true' EXIT
ditto "$CI_SMOKE_ROOT/mount/Vook4Me.app" "$CI_SMOKE_ROOT/Vook4Me.app"
hdiutil detach "$CI_SMOKE_ROOT/mount"
trap - EXIT
codesign --verify --deep --strict "$CI_SMOKE_ROOT/Vook4Me.app"
xcrun stapler validate "$CI_SMOKE_ROOT/Vook4Me.app"
spctl --assess --type execute "$CI_SMOKE_ROOT/Vook4Me.app"
CI_FIXTURE_VAULT=$(python3 -c 'from pathlib import Path; print(Path.home()/"VookReleaseFixture")')
mkdir -p "$CI_FIXTURE_VAULT"
touch "$CI_FIXTURE_VAULT/.ci-owned"
defaults write com.vook4me.app vaultLocation -string "$CI_FIXTURE_VAULT"
defaults write com.vook4me.app hasCompletedOnboarding -bool true
defaults write com.vook4me.app analyticsEnabled -bool false
defaults write com.vook4me.app remoteFaviconsEnabled -bool false
defaults write com.vook4me.app hideDockIcon -bool false
defaults write com.vook4me.app SUEnableAutomaticChecks -bool false
cp validation/ReleaseSmokeTests.swift "$CI_SMOKE_ROOT/ReleaseSmokeTests.swift"
cp -R validation/VookReleaseSmoke.xcodeproj "$CI_SMOKE_ROOT/"
open -a "$CI_SMOKE_ROOT/Vook4Me.app"
sleep 3
open -a "$CI_SMOKE_ROOT/Vook4Me.app"
xcodebuild -project "$CI_SMOKE_ROOT/VookReleaseSmoke.xcodeproj" -scheme VookReleaseSmoke \
  -destination 'platform=macOS' -derivedDataPath "$CI_SMOKE_ROOT/derived" \
  -resultBundlePath "$CI_SMOKE_ROOT/results/ReleaseSmoke.xcresult" test
