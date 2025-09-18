# 🚴‍♂️ Deployment Guide - Popi Is Biking Zen Mode

## 🎯 Automated Deployment (Recommended)

### GitHub Actions (Primary Method)

The app uses GitHub Actions for automated deployment. Every push to the `main` branch triggers an automatic deployment to GitHub Pages.

**Workflows:**
- **Primary**: `.github/workflows/deploy.yml` - Uses `peaceiris/actions-gh-pages@v3`
- **Backup**: `.github/workflows/deploy-official.yml` - Uses official GitHub Pages actions

**Features:**
- ✅ Automatic deployment on push to main
- ✅ Manual triggering via GitHub UI
- ✅ Error handling and rollback
- ✅ Build verification
- ✅ No local git operations needed

**How to use:**
1. Make your changes
2. Commit and push to `main` branch
3. GitHub Actions automatically builds and deploys
4. Monitor progress in the "Actions" tab

## 🔧 Manual Deployment (Fallback)

### Simple Deployment Script

If GitHub Actions fails, use the simple deployment script:

```bash
./deploy-simple.sh
```

**Features:**
- ✅ Step-by-step execution with error handling
- ✅ Progress feedback
- ✅ Automatic cleanup
- ✅ Rollback on failure

### Manual Steps

If the script fails, you can deploy manually:

```bash
# 1. Build the app
flutter build web --release --base-href "/popi-biking-zen-mode/" --no-wasm-dry-run

# 2. Switch to gh-pages branch
git checkout gh-pages

# 3. Clean and copy files
rm -rf *
cp -r ../build/web/* .

# 4. Commit and push
git add .
git commit -m "Deploy latest changes"
git push origin gh-pages --force

# 5. Switch back to main
git checkout main
```

## 🚨 Troubleshooting

### Common Issues

1. **Build Fails**
   - Check Flutter version compatibility
   - Verify all dependencies are installed
   - Check for linting errors

2. **Deployment Fails**
   - Verify GitHub Pages is enabled in repository settings
   - Check GitHub Actions permissions
   - Ensure `gh-pages` branch exists

3. **App Not Loading**
   - Check GitHub Pages source is set to `gh-pages` branch
   - Verify base-href matches repository name
   - Check browser console for errors

### GitHub Pages Settings

Ensure your repository has:
- **Source**: Deploy from a branch
- **Branch**: `gh-pages`
- **Folder**: `/ (root)`

## 🔐 Environment Variables

The deployment uses the following environment variables:

- `MAPTILER_API_KEY`: MapTiler API key for map tiles (optional, has fallback)

## 📊 Monitoring

- **GitHub Actions**: Check the "Actions" tab for deployment status
- **GitHub Pages**: Check repository settings > Pages for deployment status
- **App URL**: https://popisbros.github.io/popi-biking-zen-mode/

## 🎉 Success Indicators

- ✅ GitHub Actions workflow completes successfully
- ✅ `gh-pages` branch is updated
- ✅ App loads at the GitHub Pages URL
- ✅ All features work correctly

---

**Note**: The automated deployment is the recommended approach as it's more reliable and provides better error handling than manual deployment.
