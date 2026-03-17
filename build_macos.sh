#!/bin/bash

# Arctic Media - macOS Build Script
# This script builds a macOS .app bundle for Arctic Media

echo "🍎 Arctic Media - macOS Build Script"
echo "======================================"
echo ""

# Check if venv is activated
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "⚠️  Virtual environment not activated!"
    echo "Please run: source venv/bin/activate"
    exit 1
fi

# Step 1: Generate macOS icon
echo "📦 Step 1: Generating macOS icon..."
python convert_icon.py

if [ ! -f "icons/app.icns" ]; then
    echo "❌ Failed to create app.icns"
    echo "Continuing anyway..."
fi

# Step 2: Clean previous builds
echo ""
echo "🧹 Step 2: Cleaning previous builds..."
rm -rf build dist

# Step 3: Build with PyInstaller
echo ""
echo "🔨 Step 3: Building macOS app bundle..."
pyinstaller ArcticMedia-macOS.spec

# Step 4: Check if build succeeded
if [ -d "dist/ArcticMedia.app" ]; then
    echo ""
    echo "✅ Build successful!"
    echo ""
    echo "📍 Your app is located at: dist/ArcticMedia.app"
    echo ""
    echo "To test the app:"
    echo "  open dist/ArcticMedia.app"
    echo ""
    echo "To move it to Applications:"
    echo "  cp -r dist/ArcticMedia.app /Applications/"
    echo ""
else
    echo ""
    echo "❌ Build failed. Check the errors above."
    exit 1
fi
