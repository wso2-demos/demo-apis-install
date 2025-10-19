# Configuration Directory

This directory contains environment-specific parameter files for API imports.

## Structure

```
conf/
├── params.yaml.template          # Template file with examples
├── README.md                     # This file
└── <APIName_Version>/           # API-specific configuration
    └── params.yaml              # Environment parameters for this API
```

## Creating Params Files

### Step 1: Create API Directory

When you need to customize an API's import parameters:

```bash
mkdir -p conf/PizzaShackAPI_1.0.0
```

The directory name should match the exported ZIP filename (without .zip extension).

### Step 2: Copy Template

```bash
cp conf/params.yaml.template conf/PizzaShackAPI_1.0.0/params.yaml
```

### Step 3: Edit Parameters

Edit the `params.yaml` file with your environment-specific settings.

## Handling API Keys Securely (macOS)

> **Important**: Never commit API keys to version control or leave them in shell history.

Your params.yaml files should reference environment variables like `$APIKEY_QA`. Here are secure ways to set these variables on macOS:

### Method 1: Environment File (Recommended for Development)

Create a `.env` file (already in .gitignore):

```bash
# Create the secrets file in project root
cat > .env << 'EOF'
export APIKEY_DEV="your-dev-api-key"
export APIKEY_QA="your-qa-api-key"
export APIKEY_PROD="your-prod-api-key"
EOF

# Secure the file (owner read/write only)
chmod 600 .env

# Source it before running imports (doesn't expose keys in history)
source .env
./scripts/import.sh -e qa
```

**Pros**: Simple, doesn't pollute shell history, easy to update
**Cons**: Keys stored in plaintext file (but git-ignored)

### Method 2: macOS Keychain (Most Secure for Production)

Use macOS Keychain to store API keys securely:

```bash
# Store API keys in Keychain (one-time setup)
security add-generic-password -a "$USER" -s "wso2_apikey_dev" -w "your-dev-key"
security add-generic-password -a "$USER" -s "wso2_apikey_qa" -w "your-qa-key"
security add-generic-password -a "$USER" -s "wso2_apikey_prod" -w "your-prod-key"

# Retrieve and export before running imports
export APIKEY_DEV=$(security find-generic-password -a "$USER" -s "wso2_apikey_dev" -w)
export APIKEY_QA=$(security find-generic-password -a "$USER" -s "wso2_apikey_qa" -w)
export APIKEY_PROD=$(security find-generic-password -a "$USER" -s "wso2_apikey_prod" -w)

# Run import
./scripts/import.sh -e qa

# Optional: Create a helper script
cat > scripts/load-secrets.sh << 'EOF'
#!/bin/bash
export APIKEY_DEV=$(security find-generic-password -a "$USER" -s "wso2_apikey_dev" -w 2>/dev/null)
export APIKEY_QA=$(security find-generic-password -a "$USER" -s "wso2_apikey_qa" -w 2>/dev/null)
export APIKEY_PROD=$(security find-generic-password -a "$USER" -s "wso2_apikey_prod" -w 2>/dev/null)
echo "✓ Loaded API keys from Keychain"
EOF
chmod +x scripts/load-secrets.sh

# Usage
source scripts/load-secrets.sh
./scripts/import.sh -e qa
```

**Managing Keychain entries:**
```bash
# View stored keys (opens Keychain Access app)
open /System/Applications/Utilities/Keychain\ Access.app

# Update a key
security add-generic-password -a "$USER" -s "wso2_apikey_qa" -w "new-qa-key" -U

# Delete a key
security delete-generic-password -a "$USER" -s "wso2_apikey_qa"
```

**Pros**: Most secure, encrypted by macOS, survives system restarts
**Cons**: Slightly more complex setup

### Method 3: Interactive Input (Manual Entry)

Manually enter API keys when needed (won't appear in history):

```bash
# Read API key securely (input is hidden)
read -s -p "Enter QA API Key: " APIKEY_QA
echo  # New line after hidden input
export APIKEY_QA

# Verify it's set (shows only first 5 characters)
echo "API Key loaded: ${APIKEY_QA:0:5}..."

# Run import
./scripts/import.sh -e qa
```

**Pros**: Never stored anywhere, most secure for one-time use
**Cons**: Manual entry each time, prone to typos

### Method 4: Prevent History Logging

If you must use `export` directly, prevent it from being saved to shell history:

**Option A - Per-command (space prefix):**
```bash
# Note the space before 'export' - won't be saved to history
# This works if your shell has HISTCONTROL=ignorespace
 export APIKEY_QA="your-secret-key"
 export APIKEY_PROD="your-prod-key"
./scripts/import.sh -e qa
```

**Option B - Temporarily disable history:**
```bash
# Disable history temporarily
set +o history

# Set your variables
export APIKEY_QA="your-qa-key"
export APIKEY_PROD="your-prod-key"

# Re-enable history
set -o history

# Run import
./scripts/import.sh -e qa
```

**Enable ignorespace in ~/.zshrc (for zsh):**
```bash
echo 'HISTCONTROL=ignorespace' >> ~/.zshrc
source ~/.zshrc
```

**Enable ignorespace in ~/.bash_profile (for bash):**
```bash
echo 'HISTCONTROL=ignorespace' >> ~/.bash_profile
source ~/.bash_profile
```

**Pros**: Quick for temporary use
**Cons**: Easy to forget the space, still visible in process list briefly

### Method 5: Password Manager Integration

If you use 1Password, LastPass, or another password manager with CLI:

**Using 1Password CLI:**
```bash
# Install 1Password CLI
brew install --cask 1password-cli

# Sign in (one-time)
eval $(op signin)

# Store API key in 1Password (one-time)
# Create item manually in 1Password app or use CLI

# Retrieve and export
export APIKEY_QA=$(op read "op://Private/WSO2_QA_API_Key/password")
export APIKEY_PROD=$(op read "op://Private/WSO2_PROD_API_Key/password")

# Run import
./scripts/import.sh -e qa
```

**Pros**: Integrates with existing password manager, encrypted, shareable with team
**Cons**: Requires password manager CLI tool

### Alternative: Git-Ignored Params Files

If you prefer to store actual secrets directly in params.yaml files:

1. Uncomment this line in `.gitignore`:
   ```
   conf/*/params.yaml
   ```

2. Keep the template file for reference:
   ```
   !conf/params.yaml.template
   ```

3. Store actual secrets in the params.yaml files (they won't be committed)

**Pros**: Simple, no environment variable management
**Cons**: Plaintext files, easy to accidentally commit if .gitignore is misconfigured

### Comparison Table

| Method | Security | Convenience | Best For |
|--------|----------|-------------|----------|
| Environment File (.env) | Medium | High | Development |
| macOS Keychain | High | Medium | Production, Daily Use |
| Interactive Input | Highest | Low | One-time Use |
| Prevent History | Low | Low | Quick Testing |
| Password Manager | High | High | Teams, Production |
| Git-Ignored Files | Low | High | Quick Setup (Not Recommended) |

### Recommendation

**For most users**: Use **macOS Keychain (Method 2)** for production keys and **Environment File (Method 1)** for development keys.

## Common Configuration Options

### Backend Endpoints
```yaml
endpoints:
  production:
    url: https://backend.example.com/api
    config:
      apiKey: $APIKEY_PROD
```

### Virtual Hosts
```yaml
deploymentEnvironments:
  - displayOnDevportal: true
    deploymentEnvironment: UniversalGW
    deploymentVhost: api.example.com
```

### Throttling Policies
```yaml
policies:
  - Unlimited
  - Gold
  - Silver
```

### Backend Authentication
```yaml
endpoints:
  production:
    url: https://backend.example.com/api
    security:
      enabled: true
      type: basic
      username: $BACKEND_USERNAME
      password: $BACKEND_PASSWORD
```

## Documentation

For complete WSO2 API Manager params file documentation, see:
- [Migrating APIs to Different Environments](https://apim.docs.wso2.com/en/latest/install-and-setup/setup/api-controller/managing-apis-api-products/migrating-apis-to-different-environments/)
