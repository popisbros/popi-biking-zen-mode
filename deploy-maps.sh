#!/bin/bash

echo "🗺️ Deploying Interactive Maps Update..."

# Build the app
echo "📦 Building Flutter web app with interactive maps..."
flutter build web --release --base-href "/popi-biking-zen-mode/" --no-wasm-dry-run

# Create temp directory and copy files
echo "📁 Preparing deployment files..."
mkdir -p temp_deploy
cp -r build/web/* temp_deploy/

# Switch to gh-pages branch
echo "🌿 Switching to gh-pages branch..."
git checkout gh-pages

# Clear and copy files
echo "🧹 Clearing branch and copying files..."
git rm -rf . 2>/dev/null || true
cp -r temp_deploy/* .

# Commit and push
echo "💾 Committing and pushing..."
git add .
git commit -m "🗺️ Deploy interactive maps with flutter_map

✅ Added OpenStreetMap tiles with cycling-optimized view
✅ Implemented zoom controls and location centering  
✅ Interactive maps now work on web and mobile
✅ Maintained all existing UI and functionality"

git push origin gh-pages --force

# Cleanup and switch back
echo "🧹 Cleanup..."
rm -rf temp_deploy
git checkout main

echo "✅ Interactive maps deployed!"
echo "🌐 Your app with interactive maps: https://popisbros.github.io/popi-biking-zen-mode/"
