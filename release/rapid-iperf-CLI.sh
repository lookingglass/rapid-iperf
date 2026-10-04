#!/usr/bin/env bash
# rapid-iperf CLI-only version

set -euo pipefail

## config

readonly VERSION="2.0.0-beta.1-cli"
readonly REPO_URL="https://github.com/lookingglass/rapid-iperf"

readonly IP_VERSION="4" # fping IP version: 4 or 6

readonly IPERF_FOLDER_LOCATION="$HOME/.config/rapid-iperf"
readonly IPERF_SERVERS_GLOBAL_FILENAME="iperf_global.json"
readonly IPERF_SERVERS_RU_FILENAME="iperf_ru.yaml"
readonly IPERF_SERVERS_GLOBAL_FILE_LOCATION="$IPERF_FOLDER_LOCATION/$IPERF_SERVERS_GLOBAL_FILENAME"
readonly IPERF_SERVERS_RU_FILE_LOCATION="$IPERF_FOLDER_LOCATION/$IPERF_SERVERS_RU_FILENAME"

readonly IPERF_GLOBAL_LIST_URL="https://export.iperf3serverlist.net/listed_iperf3_servers.json"
readonly IPERF_RU_LIST_URL="https://raw.githubusercontent.com/itdoginfo/russian-iperf3-servers/refs/heads/main/list.yml"

readonly FPING_CMD_BASE="fping -e -q -C 1 -r 0 -B 1 -t 500"

readonly COLOR_RED=$'\e[38;2;243;139;168m'
readonly COLOR_YELLOW=$'\e[38;2;249;226;175m'
readonly COLOR_GREEN=$'\e[38;2;166;227;161m'
readonly RESET=$'\e[0m'
readonly UNDERLINE=$'\e[4m'

readonly REGIONS=("Russia" "Europe" "Asia" "North America" "Latin America" "Oceania" "Africa")
readonly IPERF_TEST_DIRECTIONS=("Upload" "Download" "Both")
readonly required_packages=("jq" "yq" "fping" "iperf3" "curl")

REGION=""
COUNT=1
DIRECTION="Upload"
OUTPUT_FORMAT=""
OUTPUT_FLAG=""
OUTPUT_FILE=""
DO_FETCH=false
tests_json="[]"

# do not edit below

function check_requirements {
    mkdir -p "$IPERF_FOLDER_LOCATION"
    if [[ ! -f "$IPERF_FOLDER_LOCATION/params.txt" ]]; then
        cat >"$IPERF_FOLDER_LOCATION/params.txt" <<EOU
# rapid-iperf custom parameters for iperf3
#
# Docs: https://iperf.fr/iperf-doc.php
#
# Do NOT include -c, -p. Those params already included
#
# Examples:
#	-P1			one parallel streaming
#	-u -b 10m		UDP test at 10 mbit/s
#	-n 1G			send 1GB while testing
#
# Enter your parameters on a single line below (no line breaks):
-P1
EOU
    fi

    local missing_packages=()
    for cmd in "${required_packages[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_packages+=("$cmd")
        fi
    done

    if ((${#missing_packages[@]} > 0)); then
        echo "Missing required packages: ${missing_packages[*]}. Install them and try again."
        exit 1
    fi
}

function check_for_updates {
    VERSION_FILE="https://raw.githubusercontent.com/lookingglass/rapid-iperf/refs/heads/main/.github/version"
    if ! LATEST_VERSION=$(curl -fsSL --connect-timeout 1 --max-time 5 "$VERSION_FILE" 2>/dev/null); then
        echo "${COLOR_RED}Error: ${RESET}Failed to check updates"
    else
        if [ "$VERSION" != "$LATEST_VERSION" ]; then
            update_available="Newest version available: $COLOR_GREEN$LATEST_VERSION$RESET
Get it from: $COLOR_YELLOW$UNDERLINE$REPO_URL$RESET"
            echo "$update_available"
        fi
    fi
}

function usage {
    local filename
    filename=$(basename "$0")
    cat <<EOU

$filename ($VERSION) | CLI iperf3 server finder & tester

Usage:

$filename --help                Display help
$filename --fetch               Fetch/update the server lists and exit
$filename --list-regions        Display list of regions
$filename --list-directions     Display list of test directions
$filename --region=<region>     Run test in a specific region (required)
$filename --count=<count>       Count of servers to test (default: 1)
$filename --direction=<dir>     Upload | Download | Both (default: Upload)
$filename --JSON                Output results as JSON
$filename --file=<path>         Send output to file

Example:
$filename --region=EU --count=3

Config directory: $IPERF_FOLDER_LOCATION
Servers loaded: $servers_counts

EOU
}

function region_mapping {
    local user_input="$1"
    local region
    case "${user_input,,}" in
    "ru" | "russia") region="Russia" ;;
    "sa" | "south america" | "latin america") region="Latin America" ;;
    "na" | "north america") region="North America" ;;
    "eu" | "europe") region="Europe" ;;
    "as" | "asia") region="Asia" ;;
    "au" | "oceania" | "oc" | "apac" | "australia") region="Oceania" ;;
    "af" | "africa") region="Africa" ;;
    *)
        echo "Unknown region '$user_input'. Use --list-regions to print all available regions"
        exit 1
        ;;
    esac
    echo "$region"
}

function direction_mapping {
    local user_input="$1"
    local direction
    case "${user_input,,}" in
    "upload" | "up" | "u") direction="Upload" ;;
    "download" | "down" | "d") direction="Download" ;;
    "both" | "b") direction="Both" ;;
    *)
        echo "Unknown direction '$user_input'. Use --list-directions to print all available directions"
        exit 1
        ;;
    esac
    echo "$direction"
}

function parse_args {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --region | --region=*)
            if [[ $1 == *=* ]]; then
                REGION=$(region_mapping "${1#*=}")
                shift
            else
                if [[ -z "${2:-}" ]]; then
                    echo "--region requires a value. Use --list-regions to see available options."
                    exit 1
                fi

                REGION=$(region_mapping "$2")
                shift 2
            fi
            ;;
        --count | --count=*)
            if [[ $1 == *=* ]]; then
                COUNT="${1#*=}"
                shift
            else
                if [[ -z "${2:-}" ]]; then
                    echo "Specify count of tests"
                    exit 1
                fi
                COUNT="$2"
                shift 2
            fi
            if [[ ! "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
                echo "--count must be an int > 0"
                exit 1
            fi
            ;;
        --direction | --direction=*)
            if [[ $1 == *=* ]]; then
                DIRECTION=$(direction_mapping "${1#*=}")
                shift
            else
                if [[ -z "${2:-}" ]]; then
                    echo "--direction requires a value. Use --list-directions to see available options."
                    exit 1
                fi
                DIRECTION=$(direction_mapping "$2")
                shift 2
            fi
            ;;
        --json | --JSON | -j)

            OUTPUT_FLAG="-J"
            shift
            ;;
        --file | --file=*)
            if [[ $1 == *=* ]]; then
                OUTPUT_FILE="${1#*=}"
                shift
            else
                if [[ -z "${2:-}" ]]; then
                    echo "File is not specified"
                    exit 1
                fi
                OUTPUT_FILE="$2"
                shift 2
            fi
            ;;
        --list-regions | --regions)
            echo "Available regions:"
            printf "%s\n" "${REGIONS[@]}"
            exit 0
            ;;
        --list-directions)
            echo "Available directions:"
            printf "%s\n" "${IPERF_TEST_DIRECTIONS[@]}"
            exit 0
            ;;
        --fetch)
            DO_FETCH=true
            shift
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1. Use --help for usage."
            exit 1
            ;;
        esac
    done
}

function fetch_iperf {
    echo "Fetching newest iperf3 server lists..."

    if curl --connect-timeout 5 -fsSL "$IPERF_GLOBAL_LIST_URL" -o "$IPERF_SERVERS_GLOBAL_FILE_LOCATION.tmp"; then
        iconv -f UTF-8 -t ASCII//TRANSLIT -c "$IPERF_SERVERS_GLOBAL_FILE_LOCATION.tmp" >"$IPERF_SERVERS_GLOBAL_FILE_LOCATION"
        rm -f "$IPERF_SERVERS_GLOBAL_FILE_LOCATION.tmp"
    else
        echo "${COLOR_RED}Error:${RESET} Failed to reach ${COLOR_YELLOW}$IPERF_GLOBAL_LIST_URL${RESET}" >&2
    fi

    if curl --connect-timeout 5 -fsSL "$IPERF_RU_LIST_URL" -o "$IPERF_SERVERS_RU_FILE_LOCATION.tmp"; then
        mv "$IPERF_SERVERS_RU_FILE_LOCATION.tmp" "$IPERF_SERVERS_RU_FILE_LOCATION"
    else
        echo "${COLOR_RED}Error:${RESET} Failed to reach ${COLOR_YELLOW}$IPERF_RU_LIST_URL${RESET}" >&2
    fi

    echo "Done."
}

function run_test {
    local host="$1"
    local port="$2"
    local test_ok=true
    local -a custom_params=()
    local -a extra_args=()
    local raw_params

    raw_params=$(awk 'NR==13 {print $0}' "$IPERF_FOLDER_LOCATION/params.txt" 2>/dev/null || true)
    if [[ -n "$raw_params" ]]; then
        read -ra custom_params <<<"$raw_params"
    fi

    [[ -n "$OUTPUT_FLAG" ]] && extra_args+=("$OUTPUT_FLAG")
    extra_args+=("${custom_params[@]}")

    local -r IPERF_TIMEOUT_SEC=30

    if [[ "$DIRECTION" == "Both" ]]; then
        if [[ -n "$OUTPUT_FLAG" ]]; then
            local upload_json="" download_json=""

            if ! upload_json=$(timeout "$IPERF_TIMEOUT_SEC" iperf3 -c "$host" -p "$port" "${extra_args[@]}"); then
                test_ok=false
            fi
            if ! download_json=$(timeout "$IPERF_TIMEOUT_SEC" iperf3 -c "$host" -p "$port" -R "${extra_args[@]}"); then
                test_ok=false
            fi

            if $test_ok; then
                jq -n --argjson upload "$upload_json" --argjson download "$download_json" \
                    '{upload: $upload, download: $download}'
            else
                jq -n '{error: "iperf3 test failed"}'
            fi
        else
            if ! timeout "$IPERF_TIMEOUT_SEC" iperf3 -c "$host" -p "$port" "${extra_args[@]}"; then
                test_ok=false
            fi
            if ! timeout "$IPERF_TIMEOUT_SEC" iperf3 -c "$host" -p "$port" -R "${extra_args[@]}"; then
                test_ok=false
            fi
        fi
    elif [[ "$DIRECTION" == "Download" ]]; then
        if ! timeout "$IPERF_TIMEOUT_SEC" iperf3 -c "$host" -p "$port" -R "${extra_args[@]}"; then
            test_ok=false
        fi
    else
        if ! timeout "$IPERF_TIMEOUT_SEC" iperf3 -c "$host" -p "$port" "${extra_args[@]}"; then
            test_ok=false
        fi
    fi

    $test_ok
}

function find_best_server {
    local cmd="$1"
    local -a servers=()
    local -a best_ip=()
    local host meta port city country isp server result new_test formatted_json

    mapfile -t servers < <(printf "%s\n" "$cmd")

    echo "Pinging ${#servers[@]} servers..." >&2

    mapfile -t best_ip < <(
        (printf "%s\n" "${servers[@]}" | cut -d'|' -f1 | $FPING_CMD_BASE -"$IP_VERSION" 2>&1 || true) |
            awk '$3 > 0 {print $1, int($3)}' |
            sort -k2 -n
    )

    if ((${#best_ip[@]} == 0)); then
        echo "No reachable servers found for this region."
        exit 1
    fi

    tests_json="[]"
    for server in "${best_ip[@]:0:$COUNT}"; do
        host=$(awk '{print $1}' <<<"$server")
        echo "Running test: $host" >&2
        meta=$(grep -F "${host}|" <<<"$cmd" | head -1)
        IFS='|' read -r _ port city country isp <<<"$meta"

        result=$(run_test "$host" "$port") || result='{"error":"iperf3 test failed"}'

        if [[ "$OUTPUT_FLAG" == "-J" ]]; then
            new_test=$(jq -n --arg test "$result" '{test: (($test | fromjson?) // $test)}')
            tests_json=$(jq --argjson new_test "$new_test" '. + [$new_test]' <<<"$tests_json")
        else
            if [[ -n "$OUTPUT_FILE" ]]; then
                echo "$result" >>"$OUTPUT_FILE"
            else
                echo "$result"
            fi
        fi
    done

    if [[ "$OUTPUT_FLAG" == "-J" ]]; then
        formatted_json=$(jq 'to_entries | map({id: .key} + .value)' <<<"$tests_json")
        if [[ -n "$OUTPUT_FILE" ]]; then
            echo "$formatted_json" >"$OUTPUT_FILE"
        else
            echo "$formatted_json" | jq
        fi
    fi
}

function run_region {
    if [[ "$REGION" == "Russia" ]]; then
        local cmd
        if ! cmd=$(yq -r '.[] | "\(.address)|\(.port)|\(.City)|RU|\(.Name)"' "$IPERF_SERVERS_RU_FILE_LOCATION" 2>/dev/null); then
            echo "Fetch servers first: run with --fetch."
            exit 1
        fi
        find_best_server "$cmd"
    else
        local cmd
        if ! cmd=$(jq -r --arg choose "$REGION" \
            '.[] | select(.CONTINENT == $choose)."IP/HOST"+"|"+."PORT"+"|"+."SITE"+"|"+."COUNTRY"+"|"+."PROVIDER"' \
            "$IPERF_SERVERS_GLOBAL_FILE_LOCATION" 2>/dev/null); then
            echo "Fetch servers first: run with --fetch."
            exit 1
        fi
        find_best_server "$cmd"
    fi
}

function get_servers_count() {
    if [[ -e "$IPERF_SERVERS_GLOBAL_FILE_LOCATION" && -e "$IPERF_SERVERS_RU_FILE_LOCATION" ]]; then
        servers_loaded_global=$(jq 'length' "$IPERF_SERVERS_GLOBAL_FILE_LOCATION" 2>/dev/null || echo 0)
        servers_loaded_ru=$(yq 'length' "$IPERF_SERVERS_RU_FILE_LOCATION" 2>/dev/null || echo 0)
        servers_loaded_total=$((servers_loaded_ru + servers_loaded_global))
    else
        servers_loaded_total=0

    fi
    printf "%s" "$servers_loaded_total"
}

function main {
    parse_args "$@"
    check_requirements
    check_for_updates
    servers_counts=$(get_servers_count)

    if $DO_FETCH; then
        fetch_iperf
        [[ -z "$REGION" ]] && exit 0
    fi

    if [[ -z "$REGION" ]]; then
        usage
        exit 1
    fi

    run_region
}

main "$@"
