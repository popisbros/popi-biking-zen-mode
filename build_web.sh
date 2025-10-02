#!/bin/bash

# Build script for web deployment with API keys
# Usage: ./build_web.sh

echo "🔨 Building Flutter Web with API keys..."

# REPLACE THESE WITH YOUR ACTUAL API KEYS
THUNDERFOREST_KEY="your_thunderforest_key_here"
MAPTILER_KEY="your_maptiler_key_here"
MAPBOX_TOKEN="your_mapbox_token_here"
LOCATIONIQ_KEY="your_locationiq_key_here"

flutter build web --release \
  --base-href="/popi-biking-zen-mode/" \
  --dart-define=THUNDERFOREST_API_KEY="$THUNDERFOREST_KEY" \
  --dart-define=MAPTILER_API_KEY="$MAPTILER_KEY" \
  --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_TOKEN" \
  --dart-define=LOCATIONIQ_API_KEY="$LOCATIONIQ_KEY"

echo "✅ Build complete! Output in build/web/"
