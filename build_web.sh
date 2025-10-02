#!/bin/bash

# Build script for web deployment
# Reads API keys from .env file and injects them at build time

echo "🔨 Building Flutter Web with API keys from .env file..."

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "👉 Copy .env.example to .env and add your API keys"
    exit 1
fi

# Load environment variables from .env
export $(cat .env | grep -v '^#' | xargs)

# Build with API keys injected
flutter build web --release \
  --base-href="/popi-biking-zen-mode/" \
  --dart-define=THUNDERFOREST_API_KEY="$THUNDERFOREST_API_KEY" \
  --dart-define=MAPTILER_API_KEY="$MAPTILER_API_KEY" \
  --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN" \
  --dart-define=LOCATIONIQ_API_KEY="$LOCATIONIQ_API_KEY"

echo "✅ Build complete! Output in build/web/"
echo "🔑 API keys were read from .env and compiled into the build"
