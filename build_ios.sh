#!/bin/bash

# Build script for iOS with API keys from .env file
# Usage: ./build_ios.sh

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please create .env from .env.example and add your API keys"
    exit 1
fi

# Load environment variables from .env
export $(cat .env | grep -v '^#' | xargs)

# Validate required keys
required_keys=("THUNDERFOREST_API_KEY" "MAPTILER_API_KEY" "MAPBOX_ACCESS_TOKEN" "LOCATIONIQ_API_KEY" "GRAPHHOPPER_API_KEY")
for key in "${required_keys[@]}"; do
    if [ -z "${!key}" ]; then
        echo "❌ Error: $key is not set in .env file"
        exit 1
    fi
done

echo "✅ All API keys found in .env"
echo "🏗️  Building iOS app..."

# Build with dart-define flags
flutter build ios --no-codesign \
    --dart-define=THUNDERFOREST_API_KEY="$THUNDERFOREST_API_KEY" \
    --dart-define=MAPTILER_API_KEY="$MAPTILER_API_KEY" \
    --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN" \
    --dart-define=LOCATIONIQ_API_KEY="$LOCATIONIQ_API_KEY" \
    --dart-define=GRAPHHOPPER_API_KEY="$GRAPHHOPPER_API_KEY"

if [ $? -eq 0 ]; then
    echo "✅ iOS build successful!"
else
    echo "❌ iOS build failed"
    exit 1
fi
