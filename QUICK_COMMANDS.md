# Quick Commands Reference

## 🚀 Most Common Commands

### Run on Your iPhone (Development)
```bash
./run_ios_device.sh
```
This replaces your old command:
```bash
# OLD (no longer works):
flutter run --release -d 00008103-000908642279001E

# NEW (use this instead):
./run_ios_device.sh
```

### Build for iOS
```bash
./build_ios.sh
```

### List Connected Devices
```bash
flutter devices
```

---

## 📝 What Changed?

**Before:**
```bash
flutter run --release -d 00008103-000908642279001E
```

**After:**
```bash
./run_ios_device.sh
```

**Why?** API keys must now be injected at build time for security. The script handles this automatically.

---

## 🔧 Manual Commands (if scripts fail)

### Run on Device with API Keys
```bash
export $(cat .env | grep -v '^#' | xargs)
flutter run --release -d 00008103-000908642279001E \
    --dart-define=THUNDERFOREST_API_KEY="$THUNDERFOREST_API_KEY" \
    --dart-define=MAPTILER_API_KEY="$MAPTILER_API_KEY" \
    --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN" \
    --dart-define=LOCATIONIQ_API_KEY="$LOCATIONIQ_API_KEY" \
    --dart-define=GRAPHHOPPER_API_KEY="$GRAPHHOPPER_API_KEY"
```

### Build for iOS with API Keys
```bash
export $(cat .env | grep -v '^#' | xargs)
flutter build ios --no-codesign \
    --dart-define=THUNDERFOREST_API_KEY="$THUNDERFOREST_API_KEY" \
    --dart-define=MAPTILER_API_KEY="$MAPTILER_API_KEY" \
    --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN" \
    --dart-define=LOCATIONIQ_API_KEY="$LOCATIONIQ_API_KEY" \
    --dart-define=GRAPHHOPPER_API_KEY="$GRAPHHOPPER_API_KEY"
```

---

## ✅ Quick Checklist

Before running:
- [ ] `.env` file exists with all 5 API keys filled in
- [ ] Graphhopper key added to `.env`
- [ ] iPhone connected via USB
- [ ] Xcode developer mode enabled

Then just run:
```bash
./run_ios_device.sh
```

That's it! 🎉
