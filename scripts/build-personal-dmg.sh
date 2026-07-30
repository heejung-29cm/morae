#!/bin/zsh
set -euo pipefail

readonly PROJECT_ROOT="${0:A:h:h}"
readonly ARTIFACT_DIR="${PROJECT_ROOT}/.artifacts"
readonly DERIVED_DATA="${ARTIFACT_DIR}/DerivedData"
readonly APP_PATH="${DERIVED_DATA}/Build/Products/Release/Morae.app"
readonly DMG_PATH="${ARTIFACT_DIR}/Morae-personal.dmg"
readonly STAGING_DIR="$(mktemp -d /tmp/morae-dmg.XXXXXX)"

cleanup() {
  rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

mkdir -p "${ARTIFACT_DIR}"

xcodebuild build \
  -project "${PROJECT_ROOT}/Morae.xcodeproj" \
  -scheme MoraeApp \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO

test -x "${APP_PATH}/Contents/MacOS/Morae"
test -x "${APP_PATH}/Contents/MacOS/hamster-event"

codesign --force --sign - "${APP_PATH}/Contents/MacOS/hamster-event"
codesign --force --sign - "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

ditto "${APP_PATH}" "${STAGING_DIR}/Morae.app"
ln -s /Applications "${STAGING_DIR}/Applications"
hdiutil create \
  -volname "Morae" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "${DMG_PATH}"
