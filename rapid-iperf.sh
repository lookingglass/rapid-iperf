#!/usr/bin/env bash

set -euo pipefail

## config

VERSION="2.0.0-beta.1"
update_available=""
REPO_URL="https://github.com/lookingglass/rapid-iperf"

IP_version="4" # fping util IP version. 4 or 6

# iperf settings

readonly IPERF_FOLDER_LOCATION="$HOME/.config/rapid-iperf"
readonly IPERF_SERVERS_GLOBAL_FILENAME="iperf_global.json"
readonly IPERF_SERVERS_RU_FILENAME="iperf_ru.yaml"
readonly IPERF_SERVERS_GLOBAL_FILE_LOCATION="$IPERF_FOLDER_LOCATION/$IPERF_SERVERS_GLOBAL_FILENAME"
readonly IPERF_SERVERS_RU_FILE_LOCATION="$IPERF_FOLDER_LOCATION/$IPERF_SERVERS_RU_FILENAME"

# do not edit below

readonly BOLD=$'\e[1m'
readonly DIM=$'\e[2m'
readonly UNDERLINE=$'\e[4m'
readonly RESET=$'\e[0m'
readonly COLOR_RED=$'\e[91m'
readonly COLOR_GREEN=$'\e[92m'
readonly COLOR_YELLOW=$'\e[93m'
readonly COLOR_BLUE=$'\e[94m'
readonly COLOR_CYAN=$'\e[96m'
readonly COLOR_WHITE=$'\e[97m'

readonly REGIONS=("Russia" "Europe" "Asia" "North America" "Latin America" "Oceania" "Africa")
readonly IPERF_TEST_DIRECTIONS=("Upload" "Download" "Both")

readonly FPING_CMD_BASE="fping -e -q -C 1 -r 0 -B 1 -t 500"
selected_direction_mode="Both"

required_packages=("jq" "yq" "fping" "iperf3" "curl")
missing_packages=()

MODE="TUI"
REGION=""
COUNT=1
DIRECTION=""
OUTPUT_FORMAT=""
OUTPUT_FLAG=""
OUTPUT_FILE=""
tests_json="[]"

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
	touch "$IPERF_FOLDER_LOCATION/favourites.txt"
	for cmd in "${required_packages[@]}"; do
		if ! command -v "$cmd" &>/dev/null; then
			missing_packages+=("$cmd")
		fi
	done
	if ((${#missing_packages[@]} == 0)); then
		printf "%s\n" "ok"
	else
		deps_status="missing"
		deps_color="$COLOR_RED"
		printf "%s\n" "$deps_color${missing_packages[*]}"
	fi

}

msgbar=""

function status {
	action=$1
	status_message=$2

	case $action in
	"set")
		msgbar="$status_message"
		;;
	"clear")
		msgbar=""
		;;
	esac
	draw
}

function ui_cursor_home {
	printf "\e[H"
}

function ui_clear_below {
	printf "\e[J"
}

function init_tui_terminal {
	tput smcup 2>/dev/null || true
	tput civis 2>/dev/null || true
}

function cleanup() {
	tput cnorm 2>/dev/null || true
	tput rmcup 2>/dev/null || true
}
function on_interrupt() {
	cleanup
	exit 130
}

function spinner() {
	local msg="$1"
	while true; do
		for f in ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏; do
			printf "\r%s %s" "$f" "$msg"
			sleep 0.1
		done
	done
}

function start_spinner() {
	spinner "$1" &
	SPINNER_PID=$!
}

function stop_spinner() {
	if [[ -n "${SPINNER_PID:-}" ]]; then
		kill "$SPINNER_PID" 2>/dev/null || true
		wait "$SPINNER_PID" 2>/dev/null || true
	fi
	SPINNER_PID=""
	printf "\r\033[K"
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

function build_header {
	local fav_count deps_status deps_color servers_count
	local ui_status=""
	fav_count=$(wc -l <"$IPERF_FOLDER_LOCATION/favourites.txt" 2>/dev/null || echo "0 found. Add by running a regular test")
	servers_count=$(get_servers_count)

	local line1 line3 line4 line5 line6

	printf -v line1 '%b%brapid-iperf%b %b- interactive iperf3 server finder & tester //%b %b%b' \
		"$BOLD" "$COLOR_WHITE" "$RESET" "$DIM" "$RESET" "$VERSION" "$ui_status"

	printf -v line3 '%bConfig:%b %b%b%s%b' \
		"$COLOR_WHITE" "$RESET" "$COLOR_BLUE" "$UNDERLINE" "$IPERF_FOLDER_LOCATION" "$RESET"

	printf -v line4 '%bDirection mode:%b %b%s%b\e[K' \
		"$COLOR_WHITE" "$RESET" "$COLOR_CYAN" "$selected_direction_mode" "$RESET"

	printf -v line5 '%bTotal servers:%b %b%s%b\e[K' \
		"$COLOR_WHITE" "$RESET" "$COLOR_BLUE" "$servers_count" "$RESET"

	printf -v line6 '%bFavourites:%b %b%s%b' \
		"$COLOR_WHITE" "$RESET" "$COLOR_BLUE" "$fav_count" "$RESET"

	if ((${#missing_packages[@]} != 0)); then
		printf -v line6 '%s\n%bDependencies missing:%b %b%s%b' \
			"$line6" \
			"$COLOR_WHITE" "$RESET" "$COLOR_RED" "${missing_packages[*]}" "$RESET"
	fi

	printf '%s\n%s\n%s\n%s\n%s\n%s\n\n' "$line1" "" "$line3" "$line4" "$line5" "$line6"
}

current=0
selected_direction_mode="Upload"

function iperf_test_direction {

	current=$((current + 1))
	if [[ $current -ge 3 ]]; then
		current=0
	fi

	selected_direction_mode=${IPERF_TEST_DIRECTIONS[$current]}
}

function check_for_updates {
	VERSION_FILE="https://raw.githubusercontent.com/lookingglass/rapid-iperf/refs/heads/main/.github/version"
	if ! LATEST_VERSION=$(curl -fsSL --connect-timeout 1 --max-time 5 "$VERSION_FILE" 2>/dev/null); then
		status "set" "${COLOR_RED}Error: ${RESET}Failed to check updates"
	else
		if [ "$VERSION" != "$LATEST_VERSION" ]; then
			update_available="Newest version available: $COLOR_GREEN$LATEST_VERSION$RESET
Get it from: $COLOR_YELLOW$UNDERLINE$REPO_URL$RESET"
			status "set" "$update_available"
		fi
	fi
}

function usage {
	local filename
	filename=$(basename "$0")
	cat <<EOU
$filename Usage:

$filename --help                Display help

$filename --list-regions        Display list of regions
$filename --list-directions     Display list of test directions
$filename --region=[region]     Run test in a specific region
$filename --count=<count>       Count of servers to test
$filename --direction=<dir>     Upload | Download | Both
$filename --format=json         Output results as JSON
$filename --file=<path>         Send JSON output to file instead of stdout

Execute without arguments to run interactive version
EOU
}

die() {
	echo "Error: $*" >&2
	exit 1
}

function region_mapping {
	USER_INPUT=$1
	local region
	case "${USER_INPUT,,}" in
	"ru" | "russia")
		region="Russia"
		;;
	"sa" | "south america")
		region="Latin America"
		;;
	"na" | "north america")
		region="North America"
		;;
	"eu" | "europe")
		region="Europe"
		;;
	"as" | "asia")
		region="Asia"
		;;
	"au" | "oceania" | "oc" | "australia")
		region="Oceania"
		;;
	"af" | "africa")
		region="Africa"
		;;
	*)
		echo "Unkworn region. Use --list-regions to list all available regions"
		exit 1
		;;
	esac
	echo "$region"
}

function parse_args {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--region | --region=*)
			if [[ $1 == *=* ]]; then
				arg_region="${1#*=}"
				REGION=$(region_mapping "$arg_region")
				shift
			else
				if [[ -z "${2:-}" ]]; then
					echo "Error: --region requires a value. Type CLI.sh --list-regions to obtain list of available regions" >&2
					exit 1
				fi
				arg_region="${2#*=}"
				REGION=$(region_mapping "$arg_region")
				shift 2
			fi
			;;
		--count | --count=*)
			if [[ $1 == *=* ]]; then
				COUNT="${1#*=}"
				shift
			else
				if [[ -z "${2:-}" ]]; then
					die "Specify count of tests"
				fi
				COUNT="$2"
				shift 2
			fi

			if [[ ! "$COUNT" =~ ^[0-9]+$ || "$COUNT" -lt 1 ]]; then
				die "--count must be a positive integer, got: $COUNT"
			fi
			;;

		--format | --format=*)
			if [[ $1 == *=* ]]; then
				OUTPUT_FORMAT="${1#*=}"
				shift
			else
				if [[ -z "${2:-}" ]]; then
					die "Available formats: JSON"
				fi
				OUTPUT_FORMAT=$2
				shift 2
			fi

			if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "JSON" ]]; then
				OUTPUT_FLAG="-J"
			else
				die "Unknown format: $OUTPUT_FORMAT. Available formats: JSON"
			fi
			;;
		--file | --file=*)
			if [[ $1 == *=* ]]; then
				OUTPUT_FILE="${1#*=}"
				shift
			else
				if [[ -z "${2:-}" ]]; then
					die "Specify a file"
				fi
				OUTPUT_FILE=$2
				shift 2
			fi
			;;
		--list-regions | --regions)
			echo "Available regions:"
			printf "%s\n" "${REGIONS[@]}"
			exit 0
			;;
		--list-directions)
			printf "%s\n" "${IPERF_TEST_DIRECTIONS[@]}"
			exit 0
			;;
		--direction | --direction=*)
			if [[ $1 == *=* ]]; then
				DIRECTION="${1#*=}"
				shift
			else
				if [[ -z "${2:-}" ]]; then
					die "--direction requires a value. Use --list-directions to see available options."
				fi
				DIRECTION="$2"
				shift 2
			fi
			;;
		--fetch)
			fetch_iperf_cli
			;;
		--help)
			usage
			exit 0
			;;
		*)
			die "Unknown option: $1. Use --help for usage."
			;;
		esac
	done
}

options=(
	"Run test"
	"Favourite servers"
	"Direction mode"
	"iperf3 params editor"
	"Fetch newest servers"
	"Quit"
)

options_install=(
	"Install"
	"Quit"
)

selected=0
function draw() {
	local i
	ui_cursor_home
	build_header
	if [[ ! ${#missing_packages[@]} == 0 ]]; then
		for i in "${!options_install[@]}"; do
			[ "$i" -eq "$selected" ] && echo -e " \e[36m$BOLD| ${options_install[$i]}\e[0m" || echo "   ${options_install[$i]}"
		done
	else

		for i in "${!options[@]}"; do
			[ "$i" -eq "$selected" ] && echo -e " \e[36m$BOLD| ${options[$i]}\e[0m" || echo "   ${options[$i]}"
		done
	fi
	echo -e "\n\e[2m[↑/↓ Navigate |  Enter/→ Select]\e[0m"
	printf '\n%s\e[K\n' "$msgbar"
	ui_clear_below
}

function run_test {
	local host=$1
	local port=$2
	local test_ok=true
	local direction
	local custom_params=("awk 'NR==13 {print $0}' "$IPERF_FOLDER_LOCATION/params.txt"")
	local extra_args=()

	if [[ "$MODE" == "CLI" ]]; then
		direction="$DIRECTION"
		IPERF_TIMEOUT_SEC=30
	else
		direction="$selected_direction_mode"
		IPERF_TIMEOUT_SEC=20
	fi

	if [[ -n "$OUTPUT_FLAG" ]]; then
		extra_args+=("$OUTPUT_FLAG")
	fi
	extra_args+=("$custom_params")

	if [[ "$direction" == "Both" ]]; then
		if [[ "$MODE" == "CLI" && -n "$OUTPUT_FLAG" ]]; then
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
	elif [[ "$direction" == "Download" ]]; then
		if ! timeout "$IPERF_TIMEOUT_SEC" iperf3 -c "$host" -p "$port" -R "${extra_args[@]}"; then
			test_ok=false
		fi
	else
		if ! timeout "$IPERF_TIMEOUT_SEC" iperf3 -c "$host" -p "$port" "${extra_args[@]}"; then
			test_ok=false
		fi
	fi

	if [[ "$MODE" != "CLI" ]]; then
		if $test_ok; then
			found=false
			if [[ -f "$IPERF_FOLDER_LOCATION/favourites.txt" ]]; then
				while IFS='|' read -r fav_host fav_port fav_city fav_country fav_isp; do
					if [[ "$fav_host" == "$host" ]]; then
						found=true
						break
					fi
				done <"$IPERF_FOLDER_LOCATION/favourites.txt"
			fi

			if ! $found; then
				read -r -p "Save this server to favourites? [y/N]: " answer
				if [[ "$answer" =~ ^[Yy] ]]; then
					echo "$host|$port|$city|$country|$isp" >>"$IPERF_FOLDER_LOCATION/favourites.txt"
				fi
			fi
		else
			echo "iperf3 test failed."
		fi

		read -n 1 -s -r -p "Press any key to continue ..."
		ui_cursor_home
		ui_clear_below
	fi
}

function find_best_server {
	local selected

	cmd=$1
	mapfile -t servers < <(printf "%s\n" "$cmd")
	local total=${#servers[@]}
	start_spinner "Pinging $total servers..."

	FPING_CMD="$FPING_CMD_BASE -$IP_version"

	mapfile -t best_ip < <(
		(printf "%s\n" "${servers[@]}" | cut -d'|' -f1 | $FPING_CMD 2>&1 || true) |
			awk '$3 > 0 {print $1, int($3)}' |
			sort -k2 -n
	)
	stop_spinner
	mapfile -t best_ip < <(printf "%s\n" "${best_ip[@]}")
	best_ip+=("Back")

	local selected=0
	local key rest
	local line host ping meta port city country isp ping_color
	local -a display_lines=()
	local -a display_lines_plain=()

	for i in "${!best_ip[@]}"; do
		line="${best_ip[$i]}"
		if [[ "$line" == "Back" ]]; then
			display_lines[$i]="Back"
			display_lines_plain[$i]="Back"
			continue
		fi
		read -r host ping <<<"$line"
		meta=$(awk -F'|' -v h="$host" '$1==h {print; exit}' <<<"$cmd")
		IFS='|' read -r _ port city country isp <<<"$meta"

		if [[ "$ping" -gt 150 ]]; then
			ping_color=$COLOR_RED
		elif [[ "$ping" -gt 70 ]]; then
			ping_color=$COLOR_YELLOW
		else
			ping_color=$COLOR_GREEN
		fi

		display_lines[$i]=$(printf "%-40s %b%-6s\e[22m\e[39m %-25s %-30s" \
			"$host" "$ping_color" "$ping" "$city, $country" "$isp")
		display_lines_plain[$i]=$(printf "%-40s %-6s %-25s %-30s" \
			"$host" "$ping" "$city, $country" "$isp")
	done

	local term_rows
	term_rows=$(tput lines 2>/dev/null || echo 24)
	local page_size=$((term_rows - 2))
	if ((page_size < 1)); then
		page_size=1
	fi

	local offset=0
	local end

	while true; do
		if ((selected < offset)); then
			offset=$selected
		fi
		if ((selected >= offset + page_size)); then
			offset=$((selected - page_size + 1))
		fi

		ui_cursor_home

		printf "\e[104m%b%-5s %-40s %-6s %-25s %-30s\e[0m\e[K\n" \
			"$BOLD" "" "Host" "Ping" "City and country" "ISP"

		end=$((offset + page_size - 1))
		if ((end >= ${#best_ip[@]})); then
			end=$((${#best_ip[@]} - 1))
		fi

		for ((i = offset; i <= end; i++)); do
			if ((i == selected)); then
				printf "\e[7m> %-3s %s\e[0m\e[K\n" "$((i + 1))" "${display_lines_plain[$i]}"
			else
				printf "  %-3s %s\e[K\n" "$((i + 1))" "${display_lines[$i]}"
			fi
		done

		ui_clear_below

		IFS= read -rsn1 key
		if [[ "$key" == $'\x1b' ]]; then
			IFS= read -rsn2 -t 0.05 rest
			[[ -n "$rest" ]] && key+="$rest"
		fi

		case "$key" in
		$'\x1b[A')
			selected=$((selected - 1))
			if ((selected < 0)); then
				selected=$((${#best_ip[@]} - 1))
			fi
			;;
		$'\x1b[B')
			selected=$((selected + 1))
			if ((selected >= ${#best_ip[@]})); then
				selected=0
			fi
			;;
		$'\x1b[C' | "")
			ui_cursor_home
			ui_clear_below

			if [[ "${best_ip[$selected]}" == "Back" ]]; then
				return 0
			fi

			read -r host ping <<<"${best_ip[$selected]}"
			meta=$(awk -F'|' -v h="$host" '$1==h {print; exit}' <<<"$cmd")
			IFS='|' read -r _ port city country isp <<<"$meta"

			if ! run_test "$host" "$port"; then
				continue
			fi
			;;
		$'\x1b')
			ui_cursor_home
			ui_clear_below
			return 0
			;;
		esac
	done

}

function cli_find_best_server {
	local cmd=$1
	local host port city country isp meta result new_test formatted_json server
	local -a servers=()
	local -a best_ip=()

	mapfile -t servers < <(printf "%s\n" "$cmd")
	local total=${#servers[@]}
	start_spinner "Pinging $total servers..."
	FPING_CMD="$FPING_CMD_BASE -$IP_version"
	mapfile -t best_ip < <(
		(printf "%s\n" "${servers[@]}" | cut -d'|' -f1 | $FPING_CMD 2>&1 || true) |
			awk '$3 > 0 {print $1, int($3)}' |
			sort -k2 -n
	)
	stop_spinner

	if ((${#best_ip[@]} == 0)); then
		die "No reachable servers found for this region."
	fi

	tests_json="[]"
	for server in "${best_ip[@]:0:$COUNT}"; do
		host=$(awk '{print $1}' <<<"$server")
		start_spinner "Running test: $host"
		meta=$(grep -F "${host}|" <<<"$cmd" | head -1)
		IFS='|' read -r _ port city country isp <<<"$meta"
		result=$(run_test "$host" "$port")
		stop_spinner
		if [[ $OUTPUT_FLAG == "-J" ]]; then
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

	if [[ $OUTPUT_FLAG == "-J" ]]; then
		# JSON formatting
		formatted_json=$(echo "$tests_json" | jq 'to_entries | map({id: .key} + .value)')

		if [[ -n "$OUTPUT_FILE" ]]; then
			echo "$formatted_json" >"$OUTPUT_FILE"
		else
			echo "$formatted_json" | jq
		fi
	fi

}

function choose_region {
	local iperf_global="$IPERF_SERVERS_GLOBAL_FILE_LOCATION"
	local iperf_ru="$IPERF_SERVERS_RU_FILE_LOCATION"
	local -a menu_items=("${REGIONS[@]}" "Back")
	local selected=0
	local key rest i

	while true; do
		ui_cursor_home

		for i in "${!menu_items[@]}"; do
			if ((i == selected)); then
				printf "\e[7m> %s\e[0m\e[K\n" "${menu_items[$i]}"
			else
				printf "  %s\e[K\n" "${menu_items[$i]}"
			fi
		done

		ui_clear_below

		IFS= read -rsn1 key
		if [[ "$key" == $'\x1b' ]]; then
			IFS= read -rsn2 -t 0.05 rest
			[[ -n "$rest" ]] && key+="$rest"
		fi

		case "$key" in
		$'\x1b[A')
			selected=$((selected - 1))
			if ((selected < 0)); then
				selected=$((${#menu_items[@]} - 1))
			fi
			;;
		$'\x1b[B')
			selected=$((selected + 1))
			if ((selected >= ${#menu_items[@]})); then
				selected=0
			fi
			;;
		$'\x1b[C' | "")
			ui_cursor_home
			ui_clear_below
			choose="${menu_items[$selected]}"
			break
			;;
		$'\x1b')
			ui_cursor_home
			ui_clear_below
			return 0
			;;
		esac
	done

	if [[ $choose == "Back" ]]; then
		return 0
	fi

	if [[ $choose == "Russia" ]]; then
		if cmd=$(yq -r '.[] | "\(.address)|\(.port)|\(.City)|RU|\(.Name)"' "$iperf_ru"); then
			find_best_server "$cmd"
		else
			status "set" "${COLOR_RED}Error: ${RESET}You have to fetch servers first. Press ${COLOR_YELLOW}Fetch newest servers${RESET} to continue"
			#read -n 1 -s -r -p "Fetch servers first. Press any key to continue ..."
		fi

	else
		if cmd=$(jq -r --arg choose "$choose" \
			'.[] | select(.CONTINENT == $choose)."IP/HOST"+"|"+."PORT"+"|"+."SITE"+"|"+."COUNTRY"+"|"+."PROVIDER"' "$iperf_global"); then
			find_best_server "$cmd"
		else
			read -n 1 -s -r -p "Fetch servers first. Press any key to continue ..."
		fi
	fi
}

function iperf3_params_editor {
	if command -v nano >/dev/null; then
		nano "$IPERF_FOLDER_LOCATION/params.txt"
	elif command -v vi >/dev/null; then
		vi "$IPERF_FOLDER_LOCATION/params.txt"
	elif command -v vim >/dev/null; then
		vim "$IPERF_FOLDER_LOCATION/params.txt"
	else
		echo "Nano or vi not found. Edit it manually at $IPERF_FOLDER_LOCATION/params.txt"
	fi

	tput rmcup 2>/dev/null || true
	tput smcup 2>/dev/null || true
	tput civis 2>/dev/null || true
	printf '\e[2J'
	ui_cursor_home
}

function select_favourite {
	if [[ ! -s "$IPERF_FOLDER_LOCATION/favourites.txt" ]]; then
		echo -e "\nError: No favourite servers found. You can add one after starting test\n"
		return 0
	fi
	mapfile -t best_ip <"$IPERF_FOLDER_LOCATION/favourites.txt"
	best_ip+=("Back")
	local selected=0
	local key rest i display_text
	local line host port city country isp

	while true; do

		ui_cursor_home

		printf "\e[104m%-5s %-40s %-25s %-20s\e[0m\e[K\n" "" "Host" "City and country" "ISP"

		for i in "${!best_ip[@]}"; do
			line="${best_ip[$i]}"
			if [[ "$line" == "Back" ]]; then
				display_text="Back"
			else
				IFS='|' read -r host port city country isp <<<"$line"
				display_text=$(printf "%-40s %-25s %-20s" "$host" "$city, $country" "$isp")
			fi

			if ((i == selected)); then
				printf "\e[7m> %-3s %s\e[0m\e[K\n" "$((i + 1))" "$display_text"
			else
				printf "  %-3s %s\e[K\n" "$((i + 1))" "$display_text"
			fi
		done
		ui_clear_below

		IFS= read -rsn1 key
		if [[ "$key" == $'\x1b' ]]; then
			IFS= read -rsn2 -t 0.05 rest
			if [[ -n "$rest" ]]; then
				key+="$rest"
			fi
		fi

		case "$key" in
		$'\x1b[A')
			selected=$((selected - 1))
			if ((selected < 0)); then
				selected=$((${#best_ip[@]} - 1))
			fi
			;;
		$'\x1b[B')
			selected=$((selected + 1))
			if ((selected >= ${#best_ip[@]})); then
				selected=0
			fi
			;;
		$'\x1b[C' | "")
			ui_cursor_home
			ui_clear_below

			if [[ "${best_ip[$selected]}" == "Back" ]]; then
				echo "back"
				return 0
			fi

			IFS='|' read -r host port city country isp <<<"${best_ip[$selected]}"
			break
			;;
		$'\x1b')
			ui_cursor_home
			ui_clear_below
			return 0
			;;
		esac
	done
	run_test "$host" "$port"
}

function fetch_iperf_cli {
	local iperf_global="$IPERF_SERVERS_GLOBAL_FILE_LOCATION"
	local iperf_ru="$IPERF_SERVERS_RU_FILE_LOCATION"
	if curl --connect-timeout 5 https://export.iperf3serverlist.net/listed_iperf3_servers.json -o "$iperf_global.tmp" >/dev/null 2>&1; then
		iconv -f UTF-8 -t ASCII//TRANSLIT -c "$iperf_global.tmp" >"$iperf_global"
	else
		echo "${COLOR_RED}Error: ${RESET}Failed to reach ${COLOR_YELLOW}https://export.iperf3serverlist.net/listed_iperf3_servers.json"
	fi
	if curl --connect-timeout 5 https://raw.githubusercontent.com/itdoginfo/russian-iperf3-servers/refs/heads/main/list.yml -o "$iperf_ru.tmp" >/dev/null 2>&1; then
		mv "$iperf_ru.tmp" "$iperf_ru"
	else
		echo "${COLOR_RED}Error: ${RESET}Failed to reach ${COLOR_YELLOW}https://raw.githubusercontent.com/itdoginfo/russian-iperf3-servers/refs/heads/main/list.yml"
	fi
	echo "Done. Start script again"
}

function fetch_iperf {
	start_spinner "Fetching newest iperf servers"
	local iperf_global="$IPERF_SERVERS_GLOBAL_FILE_LOCATION"
	local iperf_ru="$IPERF_SERVERS_RU_FILE_LOCATION"
	if curl --connect-timeout 5 https://export.iperf3serverlist.net/listed_iperf3_servers.json -o "$iperf_global.tmp" >/dev/null 2>&1; then
		iconv -f UTF-8 -t ASCII//TRANSLIT -c "$iperf_global.tmp" >"$iperf_global"
	else
		stop_spinner
		status "set" "${COLOR_RED}Error: ${RESET}Failed to reach ${COLOR_YELLOW}https://export.iperf3serverlist.net/listed_iperf3_servers.json"
		#read -n 1 -s -r -p "Press any key to continue ..."
	fi
	if curl --connect-timeout 5 https://raw.githubusercontent.com/itdoginfo/russian-iperf3-servers/refs/heads/main/list.yml -o "$iperf_ru.tmp" >/dev/null 2>&1; then
		mv "$iperf_ru.tmp" "$iperf_ru"
	else
		stop_spinner
		status "set" "${COLOR_RED}Error: ${RESET}Failed to reach ${COLOR_YELLOW}https://raw.githubusercontent.com/itdoginfo/russian-iperf3-servers/refs/heads/main/list.yml"
		#read -n 1 -s -r -p "Press any key to continue ..."
	fi
	stop_spinner
	status "set" "Fetched servers"
	draw
	return 0
}

function detect_os {
	if [[ -r /etc/os-release ]]; then
		source /etc/os-release
	else
		echo "other"
		return 0
	fi

	case "${ID:-}" in
	fedora | rhel)
		echo "redhat"
		;;

	debian | ubuntu)
		echo "debian"
		;;

	*)
		echo "other"
		;;
	esac
}

function run_cli_mode {
	if [[ -z "$REGION" ]]; then
		usage
		exit 1
	fi

	if [[ "$REGION" == "Russia" ]]; then
		if cmd=$(yq -r '.[] | "\(.address)|\(.port)|\(.City)|RU|\(.Name)"' "$IPERF_SERVERS_RU_FILE_LOCATION"); then
			cli_find_best_server "$cmd"
		else
			die "Fetch servers first: run the script with no arguments and choose 'Fetch newest servers'."
		fi
	else
		if cmd=$(jq -r --arg choose "$REGION" \
			'.[] | select(.CONTINENT == $choose)."IP/HOST"+"|"+."PORT"+"|"+."SITE"+"|"+."COUNTRY"+"|"+."PROVIDER"' "$IPERF_SERVERS_GLOBAL_FILE_LOCATION"); then
			cli_find_best_server "$cmd"
		else
			die "Fetch servers first: run the script with no arguments and choose 'Fetch newest servers'."
		fi
	fi
}
if [[ $# -gt 0 ]]; then
	MODE="CLI"
	parse_args "$@"
	run_cli_mode
else
	MODE="TUI"

	init_tui_terminal
	trap cleanup EXIT
	trap on_interrupt INT TERM
	trap 'stop_spinner; exit 130' INT

	check_requirements >/dev/null
	check_for_updates

	while true; do
		ui_cursor_home
		draw

		IFS= read -rsn1 key
		if [[ "$key" == $'\x1b' ]]; then
			IFS= read -rsn2 -t 0.05 rest
			[[ -n "$rest" ]] && key+="$rest"
		fi

		case "$key" in
		$'\x1b[A')
			if ((${#missing_packages[@]} != 0)); then
				selected=$(((selected - 1 + ${#options_install[@]}) % ${#options_install[@]}))
			else
				selected=$(((selected - 1 + ${#options[@]}) % ${#options[@]}))
			fi
			;;
		$'\x1b[B')
			if ((${#missing_packages[@]} != 0)); then
				selected=$(((selected + 1) % ${#options_install[@]}))
			else
				selected=$(((selected + 1) % ${#options[@]}))
			fi
			;;
		$'\x1b[C' | "")

			if [[ ! ${#missing_packages[@]} == 0 ]]; then
				case "${options_install[$selected]}" in
				"Install")
					os_type=$(detect_os)
					case "$os_type" in
					debian)
						sudo apt install "${missing_packages[@]}" -y
						;;
					redhat)
						sudo dnf install "${missing_packages[@]}"
						;;
					*)
						echo "Failed to install: Unknown OS. Install requirements manually" || exit 1
						;;
					esac
					read -n 1 -s -r -p "Success! Start script again to continue"
					exit 1
					;;
				"Quit")
					exit 1
					;;

				esac
			else
				set +u
				case "${options[$selected]}" in
				"Run test")
					if [[ "$servers_loaded_total" == "0" ]]; then
						status "set" "fetch servers first"
					else
						choose_region
					fi
					set -u
					;;

				"Favourite servers")
					select_favourite
					;;

				"iperf3 params editor")
					iperf3_params_editor
					ui_cursor_home
					ui_clear_below
					;;

				"Direction"*)
					iperf_test_direction
					;;
				"Fetch newest servers")
					draw
					fetch_iperf
					;;
				"Install")
					echo "install"
					exit 1
					;;
				"Quit")
					break
					;;
				esac
			fi

			;;
		esac
	done

	tput cnorm
fi
