#!/bin/bash

# 🚴‍♂️ Manual Deployment Script for Popi Is Biking Zen Mode
# Use this if GitHub Actions continues to fail

set -e  # Exit on any error

echo "🚀 Starting manual deployment..."

# Step 1: Build the app
echo "📦 Building Flutter web app..."
if ! flutter build web --release --base-href "/popi-biking-zen-mode/" --no-wasm-dry-run; then
    echo "❌ Build failed"
    exit 1
fi

# Step 2: Verify build
echo "📋 Verifying build..."
if [ ! -f "build/web/index.html" ]; then
    echo "❌ index.html not found"
    exit 1
fi

if [ ! -f "build/web/main.dart.js" ]; then
    echo "❌ main.dart.js not found"
    exit 1
fi

echo "✅ Build verification passed"

# Step 3: Prepare deployment
echo "📁 Preparing deployment..."
mkdir -p temp_deploy
cp -r build/web/* temp_deploy/

# Step 4: Deploy to gh-pages
echo "🌿 Deploying to gh-pages branch..."
git checkout gh-pages
git rm -rf . 2>/dev/null || true
cp -r temp_deploy/* .
git add .
git commit -m "🚴‍♂️ Manual deploy: Enhanced cycling features

✅ Interactive maps with flutter_map
✅ Multiple map layers (OpenStreetMap, Cycling, Satellite, Terrain, Dark)
✅ POI markers and cycling routes
✅ Community warnings system
✅ Toggle controls for all features
✅ Modern UI with cycling-optimized design"

git push origin gh-pages --force

# Step 5: Cleanup
echo "🧹 Cleanup..."
rm -rf temp_deploy
git checkout main

echo "✅ Manual deployment completed!"
echo "🌐 Your app is available at: https://popisbros.github.io/popi-biking-zen-mode/"
