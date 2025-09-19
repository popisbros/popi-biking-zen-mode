# Firebase Configuration for GitHub Pages

## CORS Error Fix

The error you're seeing is due to Firebase not being configured to allow requests from your GitHub Pages domain.

### Steps to Fix:

1. **Go to Firebase Console**
   - Visit: https://console.firebase.google.com/
   - Select project: `popi-biking-zen-mode`

2. **Configure Authentication**
   - Go to **Authentication** → **Settings** → **Authorized domains**
   - Add these domains:
     - `popisbros.github.io` (your GitHub Pages domain)
     - `localhost` (for local development)
     - `127.0.0.1` (for local development)

3. **Configure Firestore Security Rules**
   - Go to **Firestore Database** → **Rules**
   - Update rules to allow read/write access (for development):
   ```javascript
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       // Allow read/write access to all documents (for development)
       match /{document=**} {
         allow read, write: if true;
       }
     }
   }
   ```

4. **Configure API Key Restrictions (Optional)**
   - Go to **Project Settings** → **General** → **Web API Key**
   - Click on the API key to configure restrictions
   - Add HTTP referrers:
     - `https://popisbros.github.io/*`
     - `http://localhost:*` (for development)

### Current Firebase Configuration:
- **Project ID**: `popi-biking-zen-mode`
- **Auth Domain**: `popi-biking-zen-mode.firebaseapp.com`
- **Storage Bucket**: `popi-biking-zen-mode.firebasestorage.app`

### After Configuration:
1. Wait 5-10 minutes for changes to propagate
2. Test your app again
3. The CORS error should be resolved

### For Production:
Consider implementing proper Firestore security rules instead of allowing all access.
