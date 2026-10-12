#!/bin/bash
set -euo pipefail

EXPECT_VERSION="2.10.0"
APP="${BUILT_PRODUCTS_DIR:?}/${1:-Talkiie.app}"
FW="$APP/Contents/Frameworks/Sparkle.framework"
[ -d "$FW" ] || { echo "error: $FW 不存在（Sparkle 沒有被嵌入？）"; exit 1; }

got=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$FW/Resources/Info.plist" 2>/dev/null || true)
[ "$got" = "$EXPECT_VERSION" ] || { echo "error: Sparkle.framework 是 ${got:-?}，預期 ${EXPECT_VERSION}（project.yml 與本檔要一起改）"; exit 1; }

for d in XPCServices Headers PrivateHeaders Modules; do
  rm -rf "${FW:?}/Versions/B/$d" "${FW:?}/$d"
done

PART=(codesign --force --sign - --timestamp=none --preserve-metadata=identifier,flags)
[ "${CONFIGURATION:-}" = "Release" ] && PART+=(--options runtime)
"${PART[@]}" "$FW/Versions/B/Autoupdate"
"${PART[@]}" "$FW/Versions/B/Updater.app"
"${PART[@]}" "$FW"
codesign --force --sign - --timestamp=none --preserve-metadata=identifier,entitlements,requirements,flags "$APP"
codesign --verify --deep --strict "$APP"
echo "sparkle-embed: Sparkle ${got}，XPCServices 已移除，由內而外重簽（ad-hoc，${CONFIGURATION:-?}），驗證通過"
