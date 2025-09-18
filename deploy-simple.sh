#!/bin/bash

# 🚴‍♂️ Simple Deployment Script for Popi Is Biking Zen Mode
# This is a fallback option if GitHub Actions fails

set -e  # Exit on any error

echo "🚀 Starting simple deployment..."

# Step 1: Build the app
echo "📦 Building Flutter web app..."
if ! flutter build web --release --base-href "/popi-biking-zen-mode/" --no-wasm-dry-run; then
    echo "❌ Build failed"
    exit 1
fi

# Step 2: Prepare deployment files
echo "📁 Preparing deployment files..."
mkdir -p temp_deploy
cp -r build/web/* temp_deploy/

# Step 3: Switch to gh-pages branch
echo "🌿 Switching to gh-pages branch..."
if ! git checkout gh-pages; then
    echo "❌ Failed to checkout gh-pages branch"
    exit 1
fi

# Step 4: Clean and copy files
echo "🧹 Cleaning branch and copying files..."
git rm -rf . 2>/dev/null || true
cp -r temp_deploy/* .

# Step 5: Commit and push
echo "💾 Committing and pushing..."
git add .
if ! git commit -m "🚴‍♂️ Deploy enhanced cycling features

✅ Added cycling-specific tile layers (Thunderforest, MapTiler)
✅ Implemented interactive POI markers (bike shops, repair stations, water fountains)
✅ Added cycling route polylines with different colors
✅ Implemented map layer switching (OpenStreetMap, Cycling, Satellite, Terrain, Dark)
✅ Added toggle controls for POIs, routes, and warnings
✅ Enhanced map styling with cycling-optimized colors
✅ Interactive markers with detailed information dialogs
✅ Modern UI with floating action buttons for all controls

Features:
- 🗺️ 5 different map layers to choose from
- 🚲 Cycling-optimized tile layers
- 📍 Interactive POI markers with details
- 🛣️ Route visualization with polylines
- ⚠️ Community warning system
- 🎮 Intuitive toggle controls
- 📱 Responsive design for web and mobile"; then
    echo "❌ Failed to commit changes"
    exit 1
fi

if ! git push origin gh-pages --force; then
    echo "❌ Failed to push to GitHub"
    exit 1
fi

# Step 6: Cleanup and switch back
echo "🧹 Cleanup..."
rm -rf temp_deploy
git checkout main

echo "✅ Deployment completed successfully!"
echo "🌐 Your app is available at: https://popisbros.github.io/popi-biking-zen-mode/"
