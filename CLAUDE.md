# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a WSO2 API Manager backup utility that provides automated API export functionality. The project consists of a bash script that uses the WSO2 `apictl` command-line tool to export all APIs from a WSO2 API Manager environment.

## Key Components

- **scripts/backup.sh**: Main bash script for bulk API export from WSO2 API Manager
- **scripts/import.sh**: Script for importing exported APIs to target environment (e.g., QA)
- **api-exports/**: Directory containing exported API definitions (created during execution)
- **logs/**: Directory containing timestamped log files for export and import operations
- **conf/**: Configuration directory (currently empty, available for future use)

## Common Commands

### Running the Export Script

```bash
# Export all APIs (default behavior)
./scripts/backup.sh

# Export from specific environment
./scripts/backup.sh -e production

# Export to custom directory
./scripts/backup.sh -d /path/to/custom/exports

# Preview what would be exported (dry-run mode)
./scripts/backup.sh --dry-run

# Preview with filters before actual export
./scripts/backup.sh --filter 'Payment*' --dry-run

# Filter APIs by name pattern (wildcards supported)
./scripts/backup.sh --filter 'Payment*'
./scripts/backup.sh --filter 'Payment*' --filter 'PizzaShack*'

# Export specific APIs by name and version
./scripts/backup.sh --api 'PizzaShackAPI:1.0.0'
./scripts/backup.sh --api 'PizzaShackAPI:1.0.0' --api 'PetStore:2.0.0'

# Filter by provider
./scripts/backup.sh --provider admin

# Filter by status (CREATED, PUBLISHED, DEPRECATED, etc.)
./scripts/backup.sh --status PUBLISHED

# Combine filters for precise control
./scripts/backup.sh --filter 'Payment*' --provider admin --status PUBLISHED

# Clean all log files (interactive confirmation)
./scripts/backup.sh --clean-logs

# Show help
./scripts/backup.sh -h
```

### Running the Import Script

```bash
# Basic import to default environment (qa)
./scripts/import.sh

# Import to specific environment
./scripts/import.sh -e production

# Import from custom directory
./scripts/import.sh -d /path/to/exports

# Import specific API by name and version
./scripts/import.sh -a PizzaShackAPI_1.0.0 -e qa
./scripts/import.sh -a OpenAIAPI_2.3.0 -s dev -e production

# Clean all log files (interactive confirmation)
./scripts/import.sh --clean-logs

# Show help
./scripts/import.sh -h
```

### Prerequisites

Before running the script, ensure:

```bash
# Check if apictl is installed (requires v4.5+)
apictl version

# Login to WSO2 API Manager environments
apictl login dev   # source environment for export
apictl login qa    # target environment for import

# Install jq for JSON parsing (required)
brew install jq  # macOS
```

## Architecture

### Export Script (backup.sh)

The export script follows a modular approach with distinct functions:

1. **Pre-flight checks**: Validates `apictl` installation and environment connectivity
2. **API discovery**: Fetches list of all APIs using `apictl get apis`
3. **Selective filtering**: Optionally filters APIs by name pattern, specific API, or provider
4. **Bulk export**: Iterates through matching APIs and exports each one individually
5. **Logging**: Comprehensive logging with colored output and persistent log files

**Filtering Capabilities:**
- `--filter`: Match APIs by name pattern (supports wildcards like `Payment*`)
- `--api`: Export specific APIs by `Name:Version` or `Name:Version:Provider`
- `--provider`: Filter APIs by provider name
- `--status`: Filter APIs by lifecycle status (CREATED, PUBLISHED, DEPRECATED, etc.)
- `--dry-run`: Preview which APIs would be exported without performing actual export
- Filters can be combined (e.g., all Payment APIs from admin provider with PUBLISHED status)
- No filters = exports all APIs (maintains backward compatibility)

### Import Script (import.sh)

The import script provides the reverse functionality:

1. **Pre-flight checks**: Validates `apictl` installation and target environment connectivity
2. **File discovery**: Scans import directory for exported API ZIP files (all or filtered by specific API)
3. **Selective import**: Optionally import a single API by name and version
4. **Bulk import**: Imports each API file using `apictl import api --update`
5. **Logging**: Matching logging format with export script for consistency

**Selective Import Feature:**
- `--api` or `-a` flag: Import a specific API by name and version
- Format: `Name_Version` (e.g., `PizzaShackAPI_1.0.0`)
- Searches for matching ZIP file in import directory
- No flag = imports all APIs (maintains backward compatibility)

### Configuration

**Export Script ([scripts/backup.sh:7-28](scripts/backup.sh#L7-L28)):**
- `SCRIPT_DIR`: Directory where the script is located (auto-detected)
- `PROJECT_ROOT`: Project root directory (parent of scripts directory)
- `ENVIRONMENT_NAME`: Source WSO2 environment (default: "dev")
- `EXPORT_DIR`: Output directory for exports (default: `$PROJECT_ROOT/api-exports`)
- `LOG_FILE`: Generated log filename with timestamp in `$PROJECT_ROOT/logs/` directory
- `API_FILTERS`: Array of name patterns for selective export (set via `--filter`)
- `SPECIFIC_APIS`: Array of specific APIs to export (set via `--api`)
- `PROVIDER_FILTER`: Provider name filter (set via `--provider`)
- `STATUS_FILTER`: API lifecycle status filter (set via `--status`)
- `DRY_RUN`: Boolean flag for preview mode (set via `--dry-run`)

**Import Script ([scripts/import.sh:11-16](scripts/import.sh#L11-L16)):**
- `SCRIPT_DIR`: Directory where the script is located (auto-detected)
- `PROJECT_ROOT`: Project root directory (parent of scripts directory)
- `SOURCE_ENV`: Source environment name for determining import path (default: "dev")
- `IMPORT_DIR`: Source directory for API ZIP files (default: `$PROJECT_ROOT/api-exports/apis/$SOURCE_ENV`)
- `IMPORT_DIR_EXPLICIT`: Boolean flag tracking if `-d` was explicitly set (affects whether `SOURCE_ENV` is used)
- `ENVIRONMENT_NAME`: Target WSO2 environment (default: "qa")
- `API_FILTER`: Optional specific API to import (Name_Version format, set via `--api`)
- `LOG_FILE`: Generated log filename with timestamp in `$PROJECT_ROOT/logs/` directory

**Import Directory Logic:**
- If `-d/--directory` is specified: Uses the provided directory (ignores `-s`)
- If only `-s/--source-env` is specified: Constructs path as `$PROJECT_ROOT/api-exports/apis/$SOURCE_ENV`
- These options are mutually exclusive in behavior (though both can be provided, `-d` takes precedence)

### Error Handling

Both scripts include robust error handling:
- Environment connectivity validation
- Individual API operation failure tracking  
- Summary reporting of successful vs failed operations
- Comprehensive logging with colored terminal output

## Development Notes

### Export Script ([scripts/backup.sh](scripts/backup.sh))
- Updated for WSO2 `apictl` v4.5+ compatibility
- Uses new command syntax: `apictl get apis --format "{{ jsonPretty . }}"`
- Export command requires `--provider` flag: `apictl export api --name X --version Y --provider Z`
- JSON parsing with `jq` is mandatory (no fallback options)
- Export directory set via `apictl set --export-directory <path>`
- Export format is ZIP files containing API definitions in JSON format
- Logs are automatically created in `$PROJECT_ROOT/logs/` directory with timestamped filenames
- Export directory defaults to `$PROJECT_ROOT/api-exports/`
- Script uses `BASH_SOURCE` to determine its location and always uses project root for logs and exports, regardless of where it's executed from

**Selective Export Features:**
- `matches_filters()` function ([scripts/backup.sh:92-149](scripts/backup.sh#L92-L149)) implements filter logic
- Supports four filter types that can be combined:
  - **Name pattern filtering**: Uses bash pattern matching (wildcards `*` and `?`)
  - **Specific API selection**: Accepts `Name:Version` or `Name:Version:Provider` format
  - **Provider filtering**: Exact match on provider name
  - **Status filtering**: Exact match on API lifecycle status (CREATED, PUBLISHED, DEPRECATED, etc.)
- Filter behavior:
  - No filters: Exports all APIs (backward compatible)
  - Multiple `--filter` flags: OR logic (match any pattern)
  - Multiple `--api` flags: All specified APIs are exported
  - Combining filter types: AND logic (must match all applicable filters)
- API data parsing ([scripts/backup.sh:86](scripts/backup.sh#L86)) extracts `Name:Version:Provider:LifeCycleStatus`
- Summary output shows skipped API count when filters are active
- Dry-run mode displays status in square brackets `[STATUS]` for each API

**Dry-Run Mode:**
- `--dry-run` flag ([scripts/backup.sh:220-247](scripts/backup.sh#L220-L247)) enables preview mode
- Lists all APIs that would be exported with colored checkmarks
- Shows count of APIs that would be exported vs skipped
- Does not create export directory, log files, or perform any actual exports
- Useful for testing filters before running the actual export
- Can be combined with all filter options for precise preview

**Log Management:**
- `--clean-logs` flag ([scripts/backup.sh:61-87](scripts/backup.sh#L61-L87)) removes all log files
- Interactive confirmation prompt (y/N) before deletion
- Counts and displays number of log files before deletion
- Available in both backup.sh and import.sh scripts
- Operates on `$PROJECT_ROOT/logs/` directory regardless of execution location

### Import Script ([scripts/import.sh](scripts/import.sh))
- Compatible with `apictl` v4.5+ import functionality
- Uses `apictl import api --file <path> --environment <env> --update`
- `--update` flag allows overwriting existing APIs
- Automatically discovers ZIP files in import directory structure using `find`
- Supports importing from any directory structure containing API ZIP files
- Logs are automatically created in `./logs/` directory with timestamped filenames

### Key Changes from Legacy Versions

- Replaced `--format json` with `--format "{{ jsonPretty . }}"`
- Added required `--provider` parameter to export command
- Removed `--destination` flag (use `apictl set --export-directory` instead)
- Updated JSON parsing to handle Name/Version/Provider fields (capitalized)