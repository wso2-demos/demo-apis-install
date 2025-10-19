# WSO2 API Manager Backup & Import Utility

Automated scripts for exporting and importing APIs from WSO2 API Manager using the `apictl` command-line tool.

## Quick Start

### Prerequisites

```bash
# Install apictl (v4.5+)
apictl version

# Install jq for JSON parsing
brew install jq  # macOS

# Login to your environments
apictl login dev
apictl login qa
```

### Export APIs

```bash
# Export all APIs from default environment (dev)
./scripts/backup.sh

# Export with filters
./scripts/backup.sh --filter 'Payment*' --status PUBLISHED

# Preview before exporting
./scripts/backup.sh --dry-run
```

### Import APIs

```bash
# Import all APIs to default environment (qa)
./scripts/import.sh

# Import to specific environment
./scripts/import.sh -e production

# Import specific API only
./scripts/import.sh -a PizzaShackAPI_1.0.0 -e qa
```

### Configuration & API Keys

For environment-specific configurations, API keys, and security best practices:

**📖 [See Configuration Guide](conf/README.md)** - Learn how to:
- Securely manage API keys (5 methods for macOS)
- Configure environment-specific parameters
- Use params files for customizing API imports

## Features

### Export Script (`backup.sh`)
- Export all APIs or filter by name, pattern, provider, or status
- Dry-run mode to preview exports
- Comprehensive logging with colored output
- Exports to `api-exports/` directory

### Import Script (`import.sh`)
- Import all exported API ZIP files or a single specific API
- Update existing APIs automatically
- Support for environment-specific configuration via params files
- Batch processing with success/failure tracking
- Detailed import logs

## Help

Both scripts include detailed help:

```bash
./scripts/backup.sh -h
./scripts/import.sh -h
```

## Output

- **Exports**: `api-exports/` - Contains exported API ZIP files
- **Logs**: `logs/` - Timestamped log files for all operations

## Requirements

- WSO2 API Manager with `apictl` v4.5+
- `jq` for JSON parsing
- Bash 4.0+
- Active `apictl` login sessions for source/target environments
