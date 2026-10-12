#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.."

DD="build/DerivedData"; KEEP_RUNTIME=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-runtime) KEEP_RUNTIME=1; shift ;;
    --derived-data) DD="${2:?--derived-data needs a value}"; shift 2 ;;
    *) echo "build-public: unknown option $1" >&2; exit 64 ;;
  esac
done
step() { echo; echo "── $*"; }
die() { echo "build-public: ❌ $1" >&2; exit "$2"; }

command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)" 10

step "1. xcodegen generate"
xcodegen generate --quiet || die "xcodegen generate failed" 11

step "2. xcodebuild TalkiiePublic (Release, ad-hoc signed, pinned packages)"
SPM="Talkiie.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$SPM" && cp xcode/Package.resolved "$SPM/Package.resolved" || die "cannot install xcode/Package.resolved" 12
xcodebuild -project Talkiie.xcodeproj -scheme TalkiiePublic -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DD" -onlyUsePackageVersionsFromResolvedFile build \
  > build-public.log 2>&1 || { grep -E 'error:' build-public.log | head -20; die "xcodebuild failed (log: build-public.log)" 13; }
APP="$DD/Build/Products/Release/TalkiiePublic.app"
[ -d "$APP" ] || die "no app at $APP" 13
echo "build-public: ✅ $APP"

if [ "$KEEP_RUNTIME" = 0 ]; then
  step "3. re-sign ad-hoc without the hardened runtime (so the app can load Sparkle on this Mac)"
  codesign --force --sign - --timestamp=none --preserve-metadata=identifier,entitlements,requirements "$APP" \
    && codesign --verify --deep --strict "$APP" || die "re-signing failed" 14
fi

echo; echo "build-public: ✅ done"
