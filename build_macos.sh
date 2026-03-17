#!/bin/bash

# Arctic Media - macOS Build Script
# Builds a .app bundle and packages it into a distributable .dmg

set -e  # Exit on any error

APP_NAME="ArcticMedia"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
STAGING_DIR="dist/dmg_staging"

echo "Arctic Media - macOS Build Script"
echo "=================================="
echo ""

# Check if venv is activated
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "ERROR: Virtual environment not activated!"
    echo "Please run: source venv/bin/activate"
    exit 1
fi

# Step 1: Generate macOS icon
echo "Step 1: Generating macOS icon..."
python convert_icon.py

if [ ! -f "icons/app.icns" ]; then
    echo "Warning: Failed to create app.icns — continuing anyway."
fi

# Step 2: Clean previous builds
echo ""
echo "Step 2: Cleaning previous builds..."
rm -rf build dist

# Step 3: Build .app with PyInstaller
echo ""
echo "Step 3: Building macOS .app bundle..."
pyinstaller ArcticMedia-macOS.spec

if [ ! -d "dist/${APP_NAME}.app" ]; then
    echo ""
    echo "ERROR: Build failed. Check the errors above."
    exit 1
fi

echo ""
echo ".app built successfully: dist/${APP_NAME}.app"

# Step 4: Package into DMG
echo ""
echo "Step 4: Creating DMG..."

# Build staging folder: .app + Applications symlink
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -r "dist/${APP_NAME}.app" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create a writable DMG from the staging folder
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "dist/${APP_NAME}-rw.dmg"

# Convert to compressed, read-only DMG for distribution
hdiutil convert \
    "dist/${APP_NAME}-rw.dmg" \
    -format UDZO \
    -o "dist/${DMG_NAME}"

# Cleanup
rm -f "dist/${APP_NAME}-rw.dmg"
rm -rf "$STAGING_DIR"

echo ""
echo "=================================="
echo "Build complete!"
echo ""
echo "  .app  -> dist/${APP_NAME}.app"
echo "  .dmg  -> dist/${DMG_NAME}"
echo ""
echo "Distribute dist/${DMG_NAME} to your users."
echo ""
echo "Note: Users on macOS 13+ may need to right-click -> Open"
echo "on first launch if the app is not notarized."
echo ""
