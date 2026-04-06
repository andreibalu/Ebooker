#!/bin/bash
set -e

# Auto-versioning for Xcode Cloud
# - VERSION file holds major.minor (e.g. "1.1")
# - Main builds:  1.1       (build N)
# - Dev builds:   1.1.N     (build N)
# - To bump: edit VERSION to "1.2", "2.0", etc.

VERSION_FILE="$CI_PRIMARY_REPOSITORY_PATH/VERSION"
BASE_VERSION=$(cat "$VERSION_FILE")

if [ "$CI_BRANCH" = "main" ]; then
    MARKETING_VERSION="$BASE_VERSION"
else
    MARKETING_VERSION="${BASE_VERSION}.${CI_BUILD_NUMBER}"
fi

echo "Setting version to $MARKETING_VERSION (build $CI_BUILD_NUMBER)"

PBXPROJ="$CI_PRIMARY_REPOSITORY_PATH/Pageless.xcodeproj/project.pbxproj"
sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $MARKETING_VERSION;/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = .*;/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;/g" "$PBXPROJ"
