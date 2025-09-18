# 🔒 Security Guide for Popi Is Biking Zen Mode

## API Key Security

This project uses secure configuration to protect API keys and sensitive data.

### 🚨 Current Security Status

- ✅ **Environment Variables**: API keys are loaded from environment variables
- ✅ **GitHub Secrets**: Production keys are stored as GitHub repository secrets
- ✅ **Secure Configuration**: Sensitive data is not committed to the repository

### 🔧 Setting Up Secure API Keys

#### 1. For Local Development

Create a `.env` file in the project root (this file is gitignored):

```bash
# Copy the example file
cp env.example .env

# Edit .env with your real API keys
MAPTILER_API_KEY=your_real_maptiler_api_key_here
```

#### 2. For Production (GitHub Pages)

Add your API keys as GitHub repository secrets:

1. Go to your repository: https://github.com/popisbros/popi-biking-zen-mode
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add these secrets:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `MAPTILER_API_KEY` | Your MapTiler API key | `0n3hIGbHnipUHJE5pew7` |
| `FIREBASE_API_KEY` | Firebase API key (if needed) | `AIzaSyD1atb61TBjZV-IVdTagh7J2nGKMUn4QM4` |

### 🛡️ Security Best Practices

#### ✅ What's Protected:
- API keys are not visible in the public repository
- Environment variables are used for configuration
- GitHub Actions uses secrets for production builds
- Sensitive files are gitignored

#### ⚠️ Important Notes:
- **Never commit** `.env` files to version control
- **Never share** API keys in chat, email, or public forums
- **Rotate keys** regularly for better security
- **Monitor usage** of your API keys for unusual activity

### 🔄 Rotating API Keys

If you need to rotate your API keys:

1. **Generate new keys** from your service providers
2. **Update GitHub secrets** with new values
3. **Update local `.env`** file for development
4. **Test the application** to ensure everything works
5. **Revoke old keys** from your service providers

### 🚨 If API Keys Are Compromised

1. **Immediately revoke** the compromised keys
2. **Generate new keys** from your service providers
3. **Update all configurations** (GitHub secrets, local .env)
4. **Monitor for unusual activity** in your service dashboards
5. **Consider rate limiting** or additional security measures

### 📋 Security Checklist

- [ ] API keys are stored in environment variables
- [ ] `.env` file is gitignored
- [ ] GitHub secrets are configured for production
- [ ] No sensitive data is committed to the repository
- [ ] API key usage is monitored
- [ ] Keys are rotated regularly

### 🔍 Monitoring

Monitor your API key usage:
- **MapTiler**: Check usage in your MapTiler dashboard
- **Firebase**: Monitor in Firebase Console → Usage
- **GitHub Actions**: Check build logs for any errors

### 📞 Support

If you have security concerns:
1. Check this security guide first
2. Review your service provider's security documentation
3. Contact support if you suspect a security breach

---

**Remember**: Security is an ongoing process. Regularly review and update your security practices!
