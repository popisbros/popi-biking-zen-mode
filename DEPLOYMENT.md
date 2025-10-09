# Deployment Guide

## Overview

This app is hosted on **GitHub Pages**, NOT Firebase Hosting.

Firebase is only used for:
- Firestore (database)
- Crashlytics (crash reporting)

## How to Deploy

Deployment happens **automatically** via GitHub Actions when you push to `main`:

```bash
git add .
git commit -m "your message"
git push origin main
```

The GitHub Actions workflow (`.github/workflows/deploy.yml`) will:
1. Build the Flutter web app with API keys from GitHub Secrets
2. Deploy to GitHub Pages at: https://popisbros.github.io/popi-biking-zen-mode/

## What NOT to Do

❌ **DO NOT** run `firebase deploy --only hosting`
- This deploys to Firebase Hosting which is NOT used for this project
- Firebase Hosting is disabled in `firebase.json`

## Firebase Commands (Backend Only)

✅ Deploy Firestore rules only:
```bash
firebase deploy --only firestore:rules
```

✅ View Firestore data:
```bash
firebase firestore:get [path]
```

## Monitoring Deployment

Watch the deployment progress at:
https://github.com/popisbros/popi-biking-zen-mode/actions

The deployment typically takes 2-3 minutes.

## Local Development

Build locally (without deployment):
```bash
flutter build web --release
```

Run locally:
```bash
flutter run -d chrome
```
