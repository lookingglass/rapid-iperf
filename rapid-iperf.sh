#!/usr/bin/env bash
# rapid-iperf TUI+CLI version

## config

VERSION="2.0.0-release"
update_available=""
REPO_URL="https://github.com/lookingglass/rapid-iperf"

IP_version="4" # fping util IP version. 4 or 6

# iperf settings

readonly IPERF_FOLDER_LOCATION="$HOME/.config/rapid-iperf"
readonly IPERF_SERVERS_GLOBAL_FILENAME="iperf_global.json"
readonly IPERF_SERVERS_RU_FILENAME="iperf_ru.yaml"
readonly IPERF_SERVERS_GLOBAL_FILE_LOCATION="$IPERF_FOLDER_LOCATION/$IPERF_SERVERS_GLOBAL_FILENAME"
readonly IPERF_SERVERS_RU_FILE_LOCATION="$IPERF_FOLDER_LOCATION/$IPERF_SERVERS_RU_FILENAME"

readonly IPERF_GLOBAL_LIST_URL="https://export.iperf3serverlist.net/listed_iperf3_servers.json"
readonly IPERF_RU_LIST_URL="https://raw.githubusercontent.com/itdoginfo/russian-iperf3-servers/refs/heads/main/list.yml"

# do not edit below

readonly BOLD=$'\e[1m'
readonly DIM=$'\e[2m'
readonly UNDERLINE=$'\e[4m'
RESET=$'\e[0m'
COLOR_MAUVE=$'\e[38;2;203;166;247m'
COLOR_RED=$'\e[38;2;243;139;168m'
COLOR_PEACH=$'\e[38;2;250;179;135m'
COLOR_YELLOW=$'\e[38;2;249;226;175m'
COLOR_GREEN=$'\e[38;2;166;227;161m'
COLOR_SAPPHIRE=$'\e[38;2;116;199;236m'
COLOR_BLUE=$'\e[38;2;137;180;250m'
COLOR_LAVENDER=$'\e[38;2;180;190;254m'
COLOR_TEXT=$'\e[38;2;205;214;244m'

readonly REGIONS=("Russia" "Europe" "Asia" "North America" "Latin America" "Oceania" "Africa")
readonly IPERF_TEST_DIRECTIONS=("Upload" "Download" "Both")

readonly FPING_CMD_BASE="fping -e -q -C 1 -r 0 -B 1 -t 500"
selected_direction_mode="Both"

required_packages=("jq" "yq" "fping" "iperf3" "curl")
missing_packages=()

MODE="TUI"
REGION=""
COUNT=1
DIRECTION="Upload"
OUTPUT_FORMAT=""
OUTPUT_FLAG=""
OUTPUT_FILE=""
DO_FETCH=false
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

function cli_check_requirements {
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

	strip_ansi() {
		printf '%s' "$1" | sed -E $'s/\x1b\\[[0-9;]*[a-zA-Z]//g'
	}

	visible_len() {
		strip_ansi "$1" | wc -m
	}

	print_row() {
		local text="$1"
		local len pad
		len=$(visible_len "$text")
		pad=$((count - len))
		((pad < 0)) && pad=0
		printf '│ %s%*s │\n' "$text" "$pad" ""
	}

	local line1 line2 line3 line4 line5 line6
	printf -v line1 '%b%brapid-iperf%b %b-%b interactive iperf3 server finder & tester //%b %b%b%b' \
		"$BOLD" "$COLOR_MAUVE" "$RESET" "$DIM" "$RESET" "$COLOR_PEACH" "$COLOR_BLUE" "$VERSION" "$RESET"

	count=$(printf '%s' "rapid-iperf - interactive iperf3 server finder & tester // $VERSION" | wc -m)

	printf -v line3 '%bConfig:%b %b%b%s%b' \
		"$COLOR_TEXT" "$RESET" "$COLOR_RED" "$UNDERLINE" "$IPERF_FOLDER_LOCATION" "$RESET"

	printf -v line4 '%bDirection mode:%b %b%s%b' \
		"$COLOR_TEXT" "$RESET" "$COLOR_BLUE" "$selected_direction_mode" "$RESET"

	printf -v line5 '%bTotal servers:%b %b%s%b' \
		"$COLOR_TEXT" "$RESET" "$COLOR_GREEN" "$servers_count" "$RESET"

	printf -v line6 '%bFavourites:%b %b%s%b' \
		"$COLOR_TEXT" "$RESET" "$COLOR_YELLOW" "$fav_count" "$RESET"

	border=$(printf '─%.0s' $(seq $((count + 2))))

	printf '╭%s╮\n' "$border"
	print_row "$line1"
	print_row ""
	print_row "$line3"
	print_row "$line4"
	print_row "$line5"
	print_row "$line6"
	printf '╰%s╯\n\n' "$border"
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

function cli_check_for_updates {
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
			if [[ "$COUNT" =~ ^[0-9]+$ && "$COUNT" -ge 1 ]]; then
				echo "--count must be int > 0"
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
			[ "$i" -eq "$selected" ] && echo -e " ${COLOR_BLUE}${BOLD}❯ ${options_install[$i]}${RESET}" || echo -e "   ${COLOR_TEXT}${options_install[$i]}${RESET}"
		done
	else

		for i in "${!options[@]}"; do
			[ "$i" -eq "$selected" ] && echo -e " ${COLOR_BLUE}${BOLD}❯ ${options[$i]}${RESET}" || echo -e "   ${COLOR_TEXT}${options[$i]}${RESET}"
		done
	fi

	echo -e "\n${COLOR_LAVENDER}${BOLD}[↑/↓ Navigate | Enter/→ Select]${RESET}"
	printf '\n%s\e[K\n' "$msgbar"

	ui_clear_below
}

function run_test {
	local host=$1
	local port=$2
	local test_ok=true
	local direction
	local -a custom_params=()
	local extra_args=()
	local raw_params

	raw_params=$(awk 'NR==13 {print $0}' "$IPERF_FOLDER_LOCATION/params.txt" 2>/dev/null || true)
	if [[ -n "$raw_params" ]]; then
		read -ra custom_params <<<"$raw_params"
	fi

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
	extra_args+=("${custom_params[@]}")

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

	$test_ok
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
	local cmd="$1"
	local -a servers=()
	local -a best_ip=()
	local host meta port city country isp server result new_test formatted_json

	mapfile -t servers < <(printf "%s\n" "$cmd")

	echo "Pinging ${#servers[@]} servers..." >&2

	mapfile -t best_ip < <(
		(printf "%s\n" "${servers[@]}" | cut -d'|' -f1 | $FPING_CMD_BASE -"$IP_version" 2>&1 || true) |
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
			#else
			#read -n 1 -s -r -p "Fetch servers first. Press any key to continue ..."
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

function check_package_manager {

	if command -v apt >/dev/null; then
		echo "apt"
	elif command -v dnf >/dev/null; then
		echo "dnf"
	elif command -v yum >/dev/null; then
		echo "yum"
	elif command -v apk >/dev/null; then
		echo "apk"
	else
		echo "unknown"
	fi

}

function run_region {
	if [[ "$REGION" == "Russia" ]]; then
		local cmd
		if ! cmd=$(yq -r '.[] | "\(.address)|\(.port)|\(.City)|RU|\(.Name)"' "$IPERF_SERVERS_RU_FILE_LOCATION" 2>/dev/null); then
			echo "Fetch servers first: run with --fetch."
			exit 1
		fi
		cli_find_best_server "$cmd"
	else
		local cmd
		if ! cmd=$(jq -r --arg choose "$REGION" \
			'.[] | select(.CONTINENT == $choose)."IP/HOST"+"|"+."PORT"+"|"+."SITE"+"|"+."COUNTRY"+"|"+."PROVIDER"' \
			"$IPERF_SERVERS_GLOBAL_FILE_LOCATION" 2>/dev/null); then
			echo "Fetch servers first: run with --fetch."
			exit 1
		fi
		cli_find_best_server "$cmd"
	fi
}

if [[ $# -gt 0 ]]; then
	MODE="CLI"
	set -euo pipefail
	parse_args "$@"
	cli_check_requirements
	cli_check_for_updates
	servers_counts=$(get_servers_count)

	if $DO_FETCH; then
		fetch_iperf_cli
		[[ -z "$REGION" ]] && exit 0
	fi

	if [[ -z "$REGION" ]]; then
		usage
		exit 1
	fi

	run_region
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
					pm=$(check_package_manager)

					case "$pm" in
					apt)
						sudo apt install "${missing_packages[@]}" -y
						;;
					dnf)
						sudo dnf install "${missing_packages[@]}"
						;;
					yum)
						sudo yum install "${missing_packages[@]}"
						;;
					apk)
						sudo apk add "${missing_packages[@]}"
						;;
					*)
						echo -e "Failed to detect package manager. Supported package managers: apt, yum, dnf, apk\nRequired packages:"
						printf "%s\n" "${missing_packages[@]}"
						read -n 1 -s -r -p "Press any key to continue ..."
						exit 1
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
