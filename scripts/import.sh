#!/bin/bash

# WSO2 API Manager - Import APIs Script
# This script imports all APIs from exported ZIP files to a WSO2 API Manager environment using apictl

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Get the project root directory (parent of scripts directory)
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
SOURCE_ENV="dev"  # Default source environment
ENVIRONMENT_NAME="qa"  # Default target environment
IMPORT_DIR=""  # Will be set after parsing arguments
API_FILTER=""  # Optional: specific API to import (Name_Version format)

# Ensure logs directory exists in project root before creating log file
mkdir -p "$PROJECT_ROOT/logs"
LOG_FILE="$PROJECT_ROOT/logs/import_log_$(date +%Y%m%d_%H%M%S).log"
# Create the log file immediately
touch "$LOG_FILE"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
      echo -e "$1"  # Display with colors to terminal
      echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"  # Strip colors for file
  }

# Function to check if apictl is installed
check_apictl() {
    if ! command -v apictl &> /dev/null; then
        log_message "${RED}Error: apictl is not installed or not in PATH${NC}"
        log_message "Please install apictl and ensure it's in your PATH"
        exit 1
    fi
    log_message "${GREEN}✓ apictl found${NC}"
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
    log_message "${BLUE}Checking environment: $ENVIRONMENT_NAME${NC}"
    
    # Try to list APIs to test connectivity
    if apictl get apis -e "$ENVIRONMENT_NAME" &> /dev/null; then
        log_message "${GREEN}✓ Successfully connected to environment: $ENVIRONMENT_NAME${NC}"
        return 0
    else
        log_message "${RED}✗ Failed to connect to environment: $ENVIRONMENT_NAME${NC}"
        log_message "${YELLOW}Please ensure you are logged in to the environment${NC}"
        log_message "Use: apictl login $ENVIRONMENT_NAME"
        return 1
    fi
}

# Function to check if import directory exists
check_import_dir() {
    if [ ! -d "$IMPORT_DIR" ]; then
        log_message "${RED}✗ Import directory does not exist: $IMPORT_DIR${NC}"
        log_message "Please run the backup script first or specify a valid import directory"
        return 1
    fi
    log_message "${GREEN}✓ Import directory found: $IMPORT_DIR${NC}"
}

# Function to get list of API ZIP files
get_api_files() {
    # If API_FILTER is set, look for specific API
    if [ -n "$API_FILTER" ]; then
        local zip_file=$(find "$IMPORT_DIR" -name "${API_FILTER}.zip" -type f 2>/dev/null | head -n 1)

        if [ -z "$zip_file" ]; then
            # Return empty, caller will handle the error
            return 1
        fi

        echo "$zip_file"
    else
        # Find all ZIP files in the import directory structure
        local zip_files=$(find "$IMPORT_DIR" -name "*.zip" -type f 2>/dev/null)

        if [ -z "$zip_files" ]; then
            # Return empty, caller will handle the error
            return 1
        fi

        echo "$zip_files"
    fi
}

# Function to import a single API
import_api() {
    local api_file="$1"
    local api_name=$(basename "$api_file" .zip)

    log_message "${BLUE}Importing API: $api_name${NC}"
    log_message "  Source: $api_file"

    # Check for params file: conf/<api_name>/params.yaml
    local params_file="$PROJECT_ROOT/conf/$api_name/params.yaml"
    local params_flag=""

    if [ -f "$params_file" ]; then
        params_flag="--params $params_file"
        log_message "  ${YELLOW}Using params: $params_file${NC}"
    fi

    # Import the API using apictl v4.5 syntax
    if apictl import api --file "$api_file" --environment "$ENVIRONMENT_NAME" --update --insecure $params_flag 2>> "$LOG_FILE"; then
        log_message "${GREEN}✓ Successfully imported: $api_name${NC}"
        return 0
    else
        log_message "${RED}✗ Failed to import: $api_name${NC}"
        return 1
    fi
}

# Main function
main() {
    log_message "${BLUE}=== WSO2 API Manager - API Import ===${NC}"
    log_message "Started at: $(date)"
    log_message "Source Environment: $SOURCE_ENV"
    log_message "Target Environment: $ENVIRONMENT_NAME"
    log_message "Import Directory: $IMPORT_DIR"
    if [ -n "$API_FILTER" ]; then
        log_message "API Filter: $API_FILTER"
    fi
    log_message ""
    
    # Pre-flight checks
    check_apictl
    check_import_dir
    
    if ! check_environment; then
        exit 1
    fi
    
    # Get API files
    log_message "${BLUE}Getting list of API files...${NC}"
    api_files=$(get_api_files)

    if [ -z "$api_files" ]; then
        if [ -n "$API_FILTER" ]; then
            log_message "${RED}✗ API not found: ${API_FILTER}.zip${NC}"
            log_message "${YELLOW}Make sure the API name matches the format: Name_Version${NC}"
            log_message "${YELLOW}Example: PizzaShackAPI_1.0.0${NC}"
        else
            log_message "${YELLOW}⚠ No API files found in $IMPORT_DIR${NC}"
        fi
        exit 1
    fi
    
    # Count APIs
    api_count=$(echo "$api_files" | wc -l)
    log_message "${GREEN}Found $api_count API files to import${NC}"
    log_message ""
    
    # Import each API
    success_count=0
    failure_count=0
    
    while IFS= read -r api_file; do
        if [ -n "$api_file" ]; then
            if import_api "$api_file"; then
                ((success_count++))
            else
                ((failure_count++))
            fi
        fi
    done <<< "$api_files"
    
    # Summary
    log_message ""
    log_message "${BLUE}=== Import Summary ===${NC}"
    log_message "${GREEN}Successfully imported: $success_count APIs${NC}"
    if [ $failure_count -gt 0 ]; then
        log_message "${RED}Failed imports: $failure_count APIs${NC}"
    fi
    log_message "Source environment: $SOURCE_ENV"
    log_message "Target environment: $ENVIRONMENT_NAME"
    log_message "Log file: $LOG_FILE"
    log_message "Completed at: $(date)"
    
    if [ $failure_count -eq 0 ]; then
        log_message "${GREEN}🎉 All APIs imported successfully!${NC}"
        exit 0
    else
        log_message "${YELLOW}⚠ Some APIs failed to import. Check the log for details.${NC}"
        exit 1
    fi
}

# Help function
show_help() {
    echo "WSO2 API Manager - API Import Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --source-env NAME     Source environment name (default: dev)"
    echo "  -e, --environment NAME    Target environment name (default: qa)"
    echo "  -d, --directory PATH      Import directory (default: <project-root>/api-exports/apis/<source-env>)"
    echo "  -a, --api NAME_VERSION    Import specific API by name and version (e.g., PizzaShackAPI_1.0.0)"
    echo "      --clean-logs          Clean all log files from logs directory"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Prerequisites:"
    echo "  - apictl must be installed and in PATH"
    echo "  - Must be logged in to the target environment"
    echo "  - API ZIP files must exist in the import directory"
    echo ""
    echo "Configuration Overrides:"
    echo "  Optional params files can be placed in: conf/<APIName_Version>/params.yaml"
    echo "  Example: conf/OpenAIAPI_2.3.0/params.yaml"
    echo "  These files can contain environment-specific settings and override"
    echo "  the exported API definition during import"
    echo ""
    echo "Examples:"
    echo "  $0                                        # Import all APIs from dev to qa"
    echo "  $0 -s next -e qa                          # Import all APIs from next to qa"
    echo "  $0 -s dev -e production                   # Import all APIs from dev to production"
    echo "  $0 -d /path/to/exports -e production      # Custom directory to production"
    echo "  $0 -a PizzaShackAPI_1.0.0 -e qa           # Import specific API to qa"
    echo "  $0 -a OpenAIAPI_2.3.0 -s dev -e production # Import specific API from dev to production"
    echo "  $0 --clean-logs                           # Clean all log files (interactive confirmation)"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--source-env)
            SOURCE_ENV="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT_NAME="$2"
            shift 2
            ;;
        -d|--directory)
            IMPORT_DIR="$2"
            shift 2
            ;;
        -a|--api)
            API_FILTER="$2"
            shift 2
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

# Set IMPORT_DIR if not explicitly set via -d/--directory
if [ -z "$IMPORT_DIR" ]; then
    IMPORT_DIR="$PROJECT_ROOT/api-exports/apis/$SOURCE_ENV"
fi

# Run the main function
main