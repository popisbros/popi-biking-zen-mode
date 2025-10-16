# Build Instructions - Native iOS

## Prerequisites

All API keys must be provided via environment variables. **No default values are hardcoded for security reasons.**

## Setup (One-Time)

### 1. Create `.env` File

```bash
# Copy the example file
cp .env.example .env
```

### 2. Add Your API Keys to `.env`

Edit `.env` and add your actual API keys:

```env
THUNDERFOREST_API_KEY=your_actual_key_here
MAPTILER_API_KEY=your_actual_key_here
MAPBOX_ACCESS_TOKEN=your_actual_token_here
LOCATIONIQ_API_KEY=your_actual_key_here
GRAPHHOPPER_API_KEY=your_actual_key_here
```

⚠️ **Important:** The `.env` file is gitignored and should NEVER be committed.

---

## Running on iOS Device (Development)

### Option 1: Using the Run Script (Easiest) ⭐

```bash
# Run on your default device (00008103-000908642279001E)
./run_ios_device.sh

# Or specify a different device
./run_ios_device.sh <your-device-id>
```

This script will:
- ✅ Read API keys from `.env`
- ✅ Validate all keys are present
- ✅ Run `flutter run --release` with keys injected
- ✅ Deploy to your iPhone

### Option 2: Manual Run Command

```bash
# Load environment variables
export $(cat .env | grep -v '^#' | xargs)

# Run on device
flutter run --release -d 00008103-000908642279001E \
    --dart-define=THUNDERFOREST_API_KEY="$THUNDERFOREST_API_KEY" \
    --dart-define=MAPTILER_API_KEY="$MAPTILER_API_KEY" \
    --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN" \
    --dart-define=LOCATIONIQ_API_KEY="$LOCATIONIQ_API_KEY" \
    --dart-define=GRAPHHOPPER_API_KEY="$GRAPHHOPPER_API_KEY"
```

---

## Building for iOS

### Option 1: Using the Build Script (Easiest) ⭐

```bash
./build_ios.sh
```

This script will:
- ✅ Check if `.env` exists
- ✅ Validate all required API keys are present
- ✅ Build the iOS app with keys injected
- ✅ Show clear error messages if anything is missing

### Option 2: Manual Build with flutter Command

```bash
# Load environment variables
export $(cat .env | grep -v '^#' | xargs)

# Build iOS
flutter build ios --no-codesign \
    --dart-define=THUNDERFOREST_API_KEY="$THUNDERFOREST_API_KEY" \
    --dart-define=MAPTILER_API_KEY="$MAPTILER_API_KEY" \
    --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN" \
    --dart-define=LOCATIONIQ_API_KEY="$LOCATIONIQ_API_KEY" \
    --dart-define=GRAPHHOPPER_API_KEY="$GRAPHHOPPER_API_KEY"
```

### Option 3: Xcode Build

If building from Xcode, add the environment variables to your Xcode scheme:

1. Product → Scheme → Edit Scheme
2. Run → Arguments → Environment Variables
3. Add each key as a separate environment variable

---

## Troubleshooting

### ❌ Build fails with empty API keys

**Error:** Maps don't load or app crashes on startup

**Solution:**
1. Verify `.env` file exists in project root
2. Check that all 5 keys are filled in (not empty)
3. Make sure keys don't have quotes or extra spaces
4. Rebuild with the build script

### ❌ ".env file not found"

**Solution:**
```bash
cp .env.example .env
# Then edit .env with your keys
```

### ❌ Keys not being read

**Solution:** Make sure you're passing them via `--dart-define`:

The code uses `String.fromEnvironment()` which only reads compile-time constants passed via `--dart-define`, not runtime environment variables.

---

## Security Notes

✅ **Safe:**
- `.env` file (gitignored, local only)
- `--dart-define` flags (not stored in git)
- GitHub Secrets (for CI/CD)

❌ **Never:**
- Commit `.env` to git
- Hardcode keys in source code
- Share `.env` publicly

---

## GitHub Actions / CI

For automated builds, use GitHub Secrets instead of `.env`:

1. Go to: Repository Settings → Secrets and variables → Actions
2. Add each key as a secret
3. Reference in workflow: `${{ secrets.MAPBOX_ACCESS_TOKEN }}`

See `.github/workflows/` for examples.

---

## Get API Keys

- **Thunderforest**: https://www.thunderforest.com/
- **MapTiler**: https://www.maptiler.com/
- **Mapbox**: https://account.mapbox.com/
- **LocationIQ**: https://locationiq.com/
- **Graphhopper**: https://www.graphhopper.com/

---

## Summary

```bash
# Quick start for iOS build:
cp .env.example .env          # 1. Create .env
nano .env                     # 2. Add your keys
./build_ios.sh                # 3. Build!
```

That's it! 🚀
