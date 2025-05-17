#!/bin/bash

# Extract version from podspec
VERSION=$(grep -m 1 "s.version" Linkrunner.podspec | sed "s/.*= '\(.*\)'.*/\1/")

echo "Found version: $VERSION in podspec"
echo "Creating tag $VERSION..."

# Create the git tag
git tag $VERSION

# Push the git tag
git push origin $VERSION

echo "✅ Successfully created and pushed tag $VERSION"
