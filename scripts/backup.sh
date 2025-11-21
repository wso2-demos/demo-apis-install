#!/bin/bash

# WSO2 API Manager - Export All APIs Script
# This script exports all APIs from a WSO2 API Manager environment using apictl

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Get the project root directory (parent of scripts directory)
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
ENVIRONMENT_NAME="dev"  # Change this to your environment name
EXPORT_DIR="$PROJECT_ROOT/api-exports"

# Source the environment-to-version mapping configuration
ENV_CONFIG_FILE="$PROJECT_ROOT/conf/environments.conf"
if [ ! -f "$ENV_CONFIG_FILE" ]; then
    echo -e "${RED}Error: Environment configuration file not found: $ENV_CONFIG_FILE${NC}"
    echo "Please create the configuration file with environment-to-APIM version mappings"
    exit 1
fi
source "$ENV_CONFIG_FILE"

# Filter arrays for selective export
declare -a API_FILTERS=()      # API name patterns (wildcards supported)
declare -a SPECIFIC_APIS=()    # Specific API:Version combinations
PROVIDER_FILTER=""             # Provider filter
STATUS_FILTER=""               # Status filter (CREATED, PUBLISHED, DEPRECATED, etc.)
DRY_RUN=false                  # Dry-run mode (preview only, no export)

# Log file will be created later if not in dry-run mode
LOG_FILE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
      echo -e "$1"  # Display with colors to terminal
      # Only write to log file if it exists (not in dry-run mode)
      if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
          echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"  # Strip colors for file
      fi
  }

# Function to get apictl command for an environment
get_apictl_cmd() {
    local env_name="$1"
    local var_name="env_${env_name}"
    local apictl_cmd="${!var_name}"

    if [ -z "$apictl_cmd" ]; then
        log_message "${RED}Error: No APIM version mapping found for environment: $env_name${NC}"
        log_message "${YELLOW}Please add mapping in conf/environments.conf${NC}"
        log_message "${YELLOW}Example: env_${env_name}=\"apictl45\"${NC}"
        exit 1
    fi

    echo "$apictl_cmd"
}

# Function to check if apictl is installed
check_apictl() {
    local apictl_cmd=$(get_apictl_cmd "$ENVIRONMENT_NAME")

    if ! command -v "$apictl_cmd" &> /dev/null; then
        log_message "${RED}Error: $apictl_cmd is not installed or not in PATH${NC}"
        log_message "Please install $apictl_cmd for APIM version mapped to environment: $ENVIRONMENT_NAME"
        exit 1
    fi
    log_message "${GREEN}✓ $apictl_cmd found for environment $ENVIRONMENT_NAME${NC}"
}

# Function to create export directory
setup_export_dir() {
    if [ ! -d "$EXPORT_DIR" ]; then
        mkdir -p "$EXPORT_DIR"
        log_message "${GREEN}✓ Created export directory: $EXPORT_DIR${NC}"
    else
        log_message "${YELLOW}⚠ Export directory already exists: $EXPORT_DIR${NC}"
    fi
}

# Function to clean logs directory
clean_logs() {
    local logs_dir="$PROJECT_ROOT/logs"

    if [ ! -d "$logs_dir" ]; then
        echo -e "${YELLOW}⚠ Logs directory does not exist: $logs_dir${NC}"
        return 0
    fi

    local log_count=$(find "$logs_dir" -name "*.log" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [ "$log_count" -eq 0 ]; then
        echo -e "${YELLOW}⚠ No log files found in: $logs_dir${NC}"
        return 0
    fi

    echo -e "${BLUE}Found $log_count log file(s) in: $logs_dir${NC}"
    echo -e -n "${YELLOW}This will delete all log files. Continue? (y/N)${NC} "
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -f "$logs_dir"/*.log
        echo -e "${GREEN}✓ Cleaned $log_count log file(s)${NC}"
    else
        echo -e "${YELLOW}Cancelled${NC}"
    fi
}

# Function to check environment login status
check_environment() {
    local apictl_cmd=$(get_apictl_cmd "$ENVIRONMENT_NAME")
    log_message "${BLUE}Checking environment: $ENVIRONMENT_NAME (using $apictl_cmd)${NC}"

    # Try to list APIs to test connectivity
    if $apictl_cmd get apis --environment "$ENVIRONMENT_NAME" &> /dev/null; then
        log_message "${GREEN}✓ Successfully connected to environment: $ENVIRONMENT_NAME${NC}"
        return 0
    else
        log_message "${RED}✗ Failed to connect to environment: $ENVIRONMENT_NAME${NC}"
        log_message "${YELLOW}Please ensure you are logged in to the environment${NC}"
        log_message "Use: $apictl_cmd login $ENVIRONMENT_NAME"
        return 1
    fi
}

# Function to get list of APIs
get_api_list() {
    local apictl_cmd=$(get_apictl_cmd "$ENVIRONMENT_NAME")
    log_message "${BLUE}Fetching API list...${NC}"

    # Get APIs in JSON format using apictl v4.5+ syntax
    local api_data=$($apictl_cmd get apis -e "$ENVIRONMENT_NAME" --format "{{ jsonPretty . }}" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$api_data" ]; then
        log_message "${RED}✗ Failed to fetch API list${NC}"
        return 1
    fi

    # Store raw JSON data for counting
    API_JSON_DATA="$api_data"

    # Parse JSON to get API names, versions, providers, and status
    # apictl v4.5+ returns multiple JSON objects separated by newlines
    echo "$api_data" | jq -r '"\(.Name):\(.Version):\(.Provider):\(.LifeCycleStatus)"' 2>/dev/null || {
        log_message "${RED}✗ Failed to parse API data - jq is required${NC}"
        return 1
    }
}

# Function to check if API matches filters
matches_filters() {
    local api_name="$1"
    local api_version="$2"
    local api_provider="$3"
    local api_status="$4"

    # If specific APIs are defined, check if this API is in the list
    if [ ${#SPECIFIC_APIS[@]} -gt 0 ]; then
        local found=false
        for specific in "${SPECIFIC_APIS[@]}"; do
            # Support both "Name:Version" and "Name:Version:Provider" formats
            if [[ "$specific" == *":"*":"* ]]; then
                # Full format: Name:Version:Provider
                if [ "$specific" == "$api_name:$api_version:$api_provider" ]; then
                    found=true
                    break
                fi
            else
                # Short format: Name:Version (any provider)
                if [ "$specific" == "$api_name:$api_version" ]; then
                    found=true
                    break
                fi
            fi
        done
        if [ "$found" = false ]; then
            return 1  # Does not match specific API list
        fi
    fi

    # Check provider filter
    if [ -n "$PROVIDER_FILTER" ] && [ "$api_provider" != "$PROVIDER_FILTER" ]; then
        return 1  # Does not match provider filter
    fi

    # Check status filter
    if [ -n "$STATUS_FILTER" ] && [ "$api_status" != "$STATUS_FILTER" ]; then
        return 1  # Does not match status filter
    fi

    # Check API name pattern filters
    if [ ${#API_FILTERS[@]} -gt 0 ]; then
        local matches=false
        for pattern in "${API_FILTERS[@]}"; do
            # Use shell pattern matching (supports wildcards like * and ?)
            if [[ "$api_name" == $pattern ]]; then
                matches=true
                break
            fi
        done
        if [ "$matches" = false ]; then
            return 1  # Does not match any pattern
        fi
    fi

    return 0  # Matches all applicable filters
}

# Function to export a single API
export_api() {
    local api_name="$1"
    local api_version="$2"
    local api_provider="$3"
    local apictl_cmd=$(get_apictl_cmd "$ENVIRONMENT_NAME")

    log_message "${BLUE}Exporting API: $api_name (v$api_version) by $api_provider${NC}"

    # Set the export directory using apictl
    $apictl_cmd set --export-directory "$EXPORT_DIR" &>/dev/null

    # Export the API using apictl v4.5+ syntax
    if $apictl_cmd export api --name "$api_name" --version "$api_version" --provider "$api_provider" --environment "$ENVIRONMENT_NAME" --format JSON --insecure 2>> "$LOG_FILE"; then
        log_message "${GREEN}✓ Successfully exported: $api_name (v$api_version)${NC}"
        return 0
    else
        log_message "${RED}✗ Failed to export: $api_name (v$api_version)${NC}"
        return 1
    fi
}

# Function to display startup header
display_startup_header() {
    if [ "$DRY_RUN" = true ]; then
        log_message "${BLUE}=== WSO2 API Manager - DRY RUN MODE ===${NC}"
        log_message "${YELLOW}⚠ Dry-run mode: No APIs will be exported${NC}"
    else
        log_message "${BLUE}=== WSO2 API Manager - Bulk API Export ===${NC}"
    fi
    log_message "Started at: $(date)"
    log_message "Environment: $ENVIRONMENT_NAME"
    if [ "$DRY_RUN" = false ]; then
        log_message "Export Directory: $EXPORT_DIR"
    fi
    log_message ""
}

# Function to run pre-flight checks
run_preflight_checks() {
    check_apictl
    if [ "$DRY_RUN" = false ]; then
        setup_export_dir
    fi

    if ! check_environment; then
        exit 1
    fi
}

# Function to display active filters
display_active_filters() {
    if [ ${#API_FILTERS[@]} -gt 0 ] || [ ${#SPECIFIC_APIS[@]} -gt 0 ] || [ -n "$PROVIDER_FILTER" ] || [ -n "$STATUS_FILTER" ]; then
        log_message "${YELLOW}Active filters:${NC}"
        [ ${#API_FILTERS[@]} -gt 0 ] && log_message "  Name patterns: ${API_FILTERS[*]}"
        [ ${#SPECIFIC_APIS[@]} -gt 0 ] && log_message "  Specific APIs: ${SPECIFIC_APIS[*]}"
        [ -n "$PROVIDER_FILTER" ] && log_message "  Provider: $PROVIDER_FILTER"
        [ -n "$STATUS_FILTER" ] && log_message "  Status: $STATUS_FILTER"
        log_message ""
    fi
}

# Function to get and count APIs
get_and_count_apis() {
    log_message "${BLUE}Getting list of APIs...${NC}"
    api_list=$(get_api_list)

    if [ -z "$api_list" ]; then
        log_message "${YELLOW}⚠ No APIs found or failed to retrieve API list${NC}"
        exit 1
    fi

    # Count total APIs by counting JSON object starts (each object begins with '{')
    if [ -n "$API_JSON_DATA" ]; then
        total_api_count=$(echo "$API_JSON_DATA" | grep -c '^{')
    else
        total_api_count=$(echo "$api_list" | grep -c '^[^:]*:[^:]*:[^:]*:[^:]*$')
    fi
    log_message "${GREEN}Found $total_api_count total APIs${NC}"
}

# Function to handle dry-run mode
handle_dry_run() {
    log_message ""
    log_message "${BLUE}APIs that would be exported:${NC}"
    local match_count=0
    local skipped_count=0

    while IFS=':' read -r api_name api_version api_provider api_status; do
        if [ -n "$api_name" ] && [ -n "$api_version" ] && [ -n "$api_provider" ]; then
            if matches_filters "$api_name" "$api_version" "$api_provider" "$api_status"; then
                ((match_count++))
                log_message "  ${GREEN}✓${NC} $api_name (v$api_version) by $api_provider [$api_status]"
            else
                ((skipped_count++))
            fi
        fi
    done <<< "$api_list"

    log_message ""
    log_message "${BLUE}=== Dry-Run Summary ===${NC}"
    log_message "${GREEN}Would export: $match_count APIs${NC}"
    if [ $skipped_count -gt 0 ]; then
        log_message "${YELLOW}Would skip (filtered): $skipped_count APIs${NC}"
    fi
    log_message ""
    log_message "${YELLOW}To perform the actual export, run without --dry-run${NC}"
    exit 0
}

# Function to export APIs with filtering
export_apis() {
    local success_count=0
    local failure_count=0
    local skipped_count=0

    while IFS=':' read -r api_name api_version api_provider api_status; do
        if [ -n "$api_name" ] && [ -n "$api_version" ] && [ -n "$api_provider" ]; then
            # Check if API matches filters
            if matches_filters "$api_name" "$api_version" "$api_provider" "$api_status"; then
                if export_api "$api_name" "$api_version" "$api_provider"; then
                    ((success_count++))
                else
                    ((failure_count++))
                fi
            else
                ((skipped_count++))
            fi
        fi
    done <<< "$api_list"

    # Store counts in global variables for summary
    EXPORT_SUCCESS_COUNT=$success_count
    EXPORT_FAILURE_COUNT=$failure_count
    EXPORT_SKIPPED_COUNT=$skipped_count
}

# Function to display final summary
display_summary() {
    log_message ""
    log_message "${BLUE}=== Export Summary ===${NC}"
    log_message "${GREEN}Successfully exported: $EXPORT_SUCCESS_COUNT APIs${NC}"
    if [ $EXPORT_FAILURE_COUNT -gt 0 ]; then
        log_message "${RED}Failed exports: $EXPORT_FAILURE_COUNT APIs${NC}"
    fi
    if [ $EXPORT_SKIPPED_COUNT -gt 0 ]; then
        log_message "${YELLOW}Skipped (filtered): $EXPORT_SKIPPED_COUNT APIs${NC}"
    fi
    log_message "Export location: $EXPORT_DIR"
    log_message "Log file: $LOG_FILE"
    log_message "Completed at: $(date)"

    if [ $EXPORT_SUCCESS_COUNT -eq 0 ]; then
        log_message "${YELLOW}⚠ No APIs were exported. Check your filters.${NC}"
        exit 1
    elif [ $EXPORT_FAILURE_COUNT -eq 0 ]; then
        log_message "${GREEN}🎉 All matching APIs exported successfully!${NC}"
        exit 0
    else
        log_message "${YELLOW}⚠ Some APIs failed to export. Check the log for details.${NC}"
        exit 1
    fi
}

# Main function
main() {
    display_startup_header
    run_preflight_checks
    display_active_filters
    get_and_count_apis

    # Handle dry-run mode
    if [ "$DRY_RUN" = true ]; then
        handle_dry_run
    fi

    # Export APIs and display summary
    export_apis
    display_summary
}

# Help function
show_help() {
    echo "WSO2 API Manager - Bulk API Export Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment NAME      Environment name (default: dev)"
    echo "  -d, --directory PATH        Export directory (default: ./api-exports)"
    echo "  -f, --filter PATTERN        Filter APIs by name pattern (supports wildcards)"
    echo "                              Can be specified multiple times"
    echo "  -a, --api API:VERSION       Export specific API (Name:Version or Name:Version:Provider)"
    echo "                              Can be specified multiple times"
    echo "  -p, --provider NAME         Filter APIs by provider name"
    echo "  -s, --status STATUS         Filter APIs by status (CREATED, PUBLISHED, DEPRECATED, etc.)"
    echo "      --dry-run               Preview which APIs would be exported (no actual export)"
    echo "      --clean-logs            Clean all log files from logs directory"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Filter Behavior:"
    echo "  - No filters: Exports all APIs (default)"
    echo "  - With filters: Only exports APIs matching ALL specified filters"
    echo "  - Multiple --filter flags: API must match at least one pattern"
    echo "  - Multiple --api flags: All specified APIs will be exported"
    echo "  - Filters can be combined for precise control"
    echo ""
    echo "Prerequisites:"
    echo "  - Version-specific apictl must be installed and in PATH"
    echo "  - apictl45 for APIM 4.5 environments, apictl46 for APIM 4.6 environments"
    echo "  - Environment-to-version mapping configured in conf/environments.conf"
    echo "  - Must be logged in to the target environment"
    echo "  - jq is required for JSON parsing"
    echo ""
    echo "APIM Version Mapping:"
    echo "  This script uses the environment mappings defined in: conf/environments.conf"
    echo "  Current mappings:"
    for env in $ALL_ENVIRONMENTS; do
        local var_name="env_${env}"
        echo "    - $env: ${!var_name}"
    done
    echo "  To modify mappings, edit: $PROJECT_ROOT/conf/environments.conf"
    echo ""
    echo "Examples:"
    echo "  # Export all APIs (default behavior)"
    echo "  $0"
    echo ""
    echo "  # Preview what would be exported (dry-run)"
    echo "  $0 --dry-run"
    echo ""
    echo "  # Preview with filters before actual export"
    echo "  $0 --filter 'Payment*' --dry-run"
    echo ""
    echo "  # Export all APIs with names starting with 'Payment'"
    echo "  $0 --filter 'Payment*'"
    echo ""
    echo "  # Export multiple API name patterns"
    echo "  $0 --filter 'Payment*' --filter 'PizzaShack*'"
    echo ""
    echo "  # Export specific APIs by name and version"
    echo "  $0 --api 'PizzaShackAPI:1.0.0' --api 'PetStore:2.0.0'"
    echo ""
    echo "  # Export all APIs from a specific provider"
    echo "  $0 --provider admin"
    echo ""
    echo "  # Export only PUBLISHED APIs"
    echo "  $0 --status PUBLISHED"
    echo ""
    echo "  # Combine filters: Payment APIs from admin provider with PUBLISHED status"
    echo "  $0 --filter 'Payment*' --provider admin --status PUBLISHED"
    echo ""
    echo "  # Export to custom environment and directory"
    echo "  $0 -e production -d /path/to/exports --filter 'Prod*'"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT_NAME="$2"
            shift 2
            ;;
        -d|--directory)
            EXPORT_DIR="$2"
            shift 2
            ;;
        -f|--filter)
            API_FILTERS+=("$2")
            shift 2
            ;;
        -a|--api)
            SPECIFIC_APIS+=("$2")
            shift 2
            ;;
        -p|--provider)
            PROVIDER_FILTER="$2"
            shift 2
            ;;
        -s|--status)
            STATUS_FILTER="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --clean-logs)
            clean_logs
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Create log file only if not in dry-run mode
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$PROJECT_ROOT/logs"
    LOG_FILE="$PROJECT_ROOT/logs/export_log_$(date +%Y%m%d_%H%M%S).log"
    touch "$LOG_FILE"
fi

# Run the main function
main
