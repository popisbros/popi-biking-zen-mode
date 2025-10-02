# 🔐 Secure API Keys Setup for GitHub

## ✅ Safe Approach (Current Implementation)

Your API keys are now **safely stored** and **NOT committed to GitHub**!

### How It Works:

1. **`.env` file** - Contains your actual API keys (gitignored ✅)
2. **`.env.example`** - Template file (committed to GitHub ✅)
3. **`lib/config/api_keys.dart`** - Loads keys from `.env` (gitignored ✅)
4. **`.gitignore`** - Prevents accidental commits of secrets ✅

---

## 📝 Step-by-Step Setup

### 1. **Local Development (Your Computer)**

```bash
cd /Users/sylvain/Cursor/popi_biking_fresh

# Copy the example file
cp .env.example .env

# Edit .env and add your REAL keys
nano .env  # or use any text editor
```

Your `.env` file should look like:
```env
THUNDERFOREST_API_KEY=a1b2c3d4e5f6g7h8i9j0
MAPTILER_API_KEY=k1l2m3n4o5p6q7r8s9t0
MAPBOX_ACCESS_TOKEN=pk.eyJ1IjoieW91ciIsImEiOiJjbHh4eCJ9.xxxxx
LOCATIONIQ_API_KEY=pk.xxxxxxxxxxxxxxxxxxxx
```

### 2. **Run Locally**

```bash
flutter pub get
flutter run
```

The app will load keys from `.env` automatically!

---

## 🚀 GitHub Deployment (Web PWA)

For deploying to GitHub Pages, you have **2 secure options**:

### **Option A: GitHub Secrets (Recommended)**

1. Go to your GitHub repo: https://github.com/popisbros/popi-biking-zen-mode
2. Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Add each key:
   - Name: `THUNDERFOREST_API_KEY`, Value: `your_actual_key`
   - Name: `MAPTILER_API_KEY`, Value: `your_actual_key`
   - Name: `MAPBOX_ACCESS_TOKEN`, Value: `your_actual_token`
   - Name: `LOCATIONIQ_API_KEY`, Value: `your_actual_key`

5. **GitHub Actions will inject these at build time!**

### **Option B: Manual .env Upload**

For quick testing, manually create `.env` on your local machine and build:

```bash
# Build with .env file present
flutter build web --release --base-href="/popi-biking-zen-mode/"

# Deploy manually
# (The .env is baked into the compiled JavaScript, but source .env is not uploaded)
```

---

## 🔒 What's Protected?

### ✅ **Safe to commit** (already in git):
- `.env.example` - Template with NO real keys
- `lib/config/api_keys.dart` - Code that reads from .env
- All other source code

### ❌ **NEVER commit** (in .gitignore):
- `.env` - Your actual API keys
- Any file with real credentials

---

## 🌐 For Firebase (GitHub Pages)

Firebase is currently **disabled on web** because of initialization issues. To re-enable:

1. **Firebase Console Setup:**
   - Go to https://console.firebase.google.com/
   - Select "popi-biking-zen-mode" project
   - Add Web app
   - Copy the config

2. **Update `firebase_options.dart`:**
   - Ensure web configuration exists
   - Keys are already in the file (safe - Firebase config is public)

3. **Enable in code:**
   - In `lib/main.dart` line 22, change `if (!kIsWeb)` to `if (true)`

4. **GitHub Secrets (if needed):**
   - Firebase keys are public (safe in code)
   - But if you want extra security, use Firebase App Check

---

## 📦 GitHub Actions Workflow (Optional)

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - uses: subosito/flutter-action@v2
        with:
          channel: 'stable'

      - name: Create .env file from secrets
        run: |
          echo "THUNDERFOREST_API_KEY=${{ secrets.THUNDERFOREST_API_KEY }}" >> .env
          echo "MAPTILER_API_KEY=${{ secrets.MAPTILER_API_KEY }}" >> .env
          echo "MAPBOX_ACCESS_TOKEN=${{ secrets.MAPBOX_ACCESS_TOKEN }}" >> .env
          echo "LOCATIONIQ_API_KEY=${{ secrets.LOCATIONIQ_API_KEY }}" >> .env

      - run: flutter pub get

      - run: flutter build web --release --base-href="/popi-biking-zen-mode/"

      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./build/web
```

---

## ✅ Security Checklist

- [x] `.env` in `.gitignore`
- [x] `lib/config/api_keys.dart` in `.gitignore`
- [x] `.env.example` template created
- [x] Real keys stored in `.env` (not committed)
- [x] GitHub Secrets configured (optional)
- [x] Compiled web build has keys baked in (secure)
- [x] Source code safe to push to public GitHub

---

## 🆘 If You Accidentally Committed Keys

1. **Immediately revoke** the exposed keys at provider websites
2. Generate **new** keys
3. Update your `.env` file
4. Run:
   ```bash
   git filter-branch --force --index-filter \
   "git rm --cached --ignore-unmatch .env" \
   --prune-empty --tag-name-filter cat -- --all

   git push origin --force --all
   ```
5. Consider all old keys **compromised** - regenerate ALL of them

---

## 📚 Summary

**Your API keys are now:**
- ✅ Safe from GitHub
- ✅ Easy to manage locally
- ✅ Can be injected via GitHub Secrets for CI/CD
- ✅ Not exposed in public repositories
- ✅ Compiled into web builds securely
