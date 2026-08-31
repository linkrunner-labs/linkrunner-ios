---
name: deploy-sdk
description: Release a new version of the LinkrunnerKit iOS SDK — bump the podspec version, update the changelog, push a git tag, and publish to CocoaPods trunk. Use when the user asks to "release", "deploy", "publish", "ship", or "cut a new version" of the iOS SDK/pod.
---

# Deploy LinkrunnerKit (iOS SDK)

Releases are manual (no CI publishes this pod). The version of record lives in
`LinkrunnerKit.podspec` (`s.version`); the git tag must exactly match it (no `v` prefix),
because the podspec's `s.source` resolves the download from `:tag => s.version.to_s`.

## Steps

1. **Confirm you're on `main` and it's up to date.**
   ```
   git checkout main
   git pull origin main
   ```
   All version-bump commits are merged to `main` via PR first (see recent history —
   `chore: bump version X -> Y`), then tagged from `main`. Don't tag a feature branch.

2. **Bump the version.**
   Edit `s.version` in `LinkrunnerKit.podspec` (semver — patch/minor/major per the change).

3. **Update `CHANGELOG.md`.**
   Add a new `## [X.Y.Z] - YYYY-MM-DD` section at the top (below the header), following
   Keep a Changelog format (`### Added` / `### Changed` / `### Fixed` etc.), summarizing
   what shipped since the last version.

4. **Commit and open a PR.**
   ```
   git checkout -b chore/bump-version-X.Y.Z
   git add LinkrunnerKit.podspec CHANGELOG.md
   git commit -m "chore: bump version <old> -> <new>"
   git push -u origin chore/bump-version-X.Y.Z
   gh pr create --title "chore: bump version <old> -> <new>" --body "..."
   ```
   Wait for the PR to be reviewed and merged into `main` before tagging — the podspec on
   `main` at the tagged commit is what CocoaPods will fetch.

5. **After the PR is merged, sync `main` and cut the tag.**
   ```
   git checkout main
   git pull origin main
   ./release.sh
   ```
   `release.sh` reads `s.version` out of the podspec, then runs
   `git tag $VERSION && git push origin $VERSION`. Confirm with the user before this
   runs — pushing a tag is effectively public and hard to walk back once CocoaPods picks
   it up.

6. **Validate the podspec against the pushed tag.**
   ```
   pod spec lint LinkrunnerKit.podspec
   ```
   This clones the just-pushed tag and builds against it — catches source/tag mismatches
   before they hit trunk.

7. **Publish to CocoaPods trunk.**
   ```
   pod trunk push LinkrunnerKit.podspec
   ```
   Requires local trunk auth (`pod trunk me` shows the registered session/email). This
   step is irreversible for that version number — CocoaPods does not allow re-pushing the
   same version. Confirm with the user before running it.

8. **Verify the release is live.**
   ```
   pod trunk info LinkrunnerKit
   ```
   or check `https://cocoapods.org/pods/LinkrunnerKit`.

## Notes

- If `pod trunk push` fails on lint warnings, fix the podspec/source rather than passing
  `--allow-warnings` unless the user explicitly asks for it.
- SPM consumers pick up the new tag automatically once it's pushed (step 5) — no
  separate SPM publish step exists; `Package.swift` doesn't pin a version itself.
- Never run steps 5–7 on anything other than the merged `main` branch.
