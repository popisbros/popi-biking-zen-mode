#!/bin/bash

# Run script for iOS device in DEBUG mode with API keys from .env file
# Usage: ./run_ios_device_debug.sh [device_id]
# Example: ./run_ios_device_debug.sh 00008140-000014180C6A801C

# Default device ID (your iPhone)
DEFAULT_DEVICE_ID="00008140-000014180C6A801C"
DEVICE_ID="${1:-$DEFAULT_DEVICE_ID}"

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
echo "📱 Running on device: $DEVICE_ID"
echo "🐛 Starting app in DEBUG mode (for debug overlay)..."

# Run on device in DEBUG mode with dart-define flags
flutter run --debug -d "$DEVICE_ID" \
    --dart-define=THUNDERFOREST_API_KEY="$THUNDERFOREST_API_KEY" \
    --dart-define=MAPTILER_API_KEY="$MAPTILER_API_KEY" \
    --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN" \
    --dart-define=LOCATIONIQ_API_KEY="$LOCATIONIQ_API_KEY" \
    --dart-define=GRAPHHOPPER_API_KEY="$GRAPHHOPPER_API_KEY"

if [ $? -eq 0 ]; then
    echo "✅ App deployed successfully in DEBUG mode!"
else
    echo "❌ Deployment failed"
    exit 1
fi
