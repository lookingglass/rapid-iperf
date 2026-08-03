#!/usr/bin/env bash

set -euo pipefail

## config

UI_MODE=auto # auto | standard | fzf

# iperf settings

readonly IPERF_FOLDER_LOCATION="$HOME/.config/iperf_tool"

readonly IPERF_SERVERS_GLOBAL_FILENAME="iperf_global.json"
readonly IPERF_SERVERS_RU_FILENAME="iperf_ru.yaml"

readonly IPERF_SERVERS_GLOBAL_FILE_LOCATION="$IPERF_FOLDER_LOCATION/$IPERF_SERVERS_GLOBAL_FILENAME"
readonly IPERF_SERVERS_RU_FILE_LOCATION="$IPERF_FOLDER_LOCATION/$IPERF_SERVERS_RU_FILENAME"

readonly IPERF_TIMEOUT_SEC=20

# fping settings

readonly FPING_CMD="fping -e -q -C 1 -r 0 -B 1 -4 -t 500"

# colors

readonly COLOR_GREEN=$'\e[92m'
readonly COLOR_YELLOW=$'\e[93m'
readonly UNDERLINE=$'\e[4m'

readonly PING_COLOR_LOW="\e[1;32m"
readonly PING_COLOR_MEDIUM="\e[1;33m"
readonly PING_COLOR_HIGH="\e[1;31m"

readonly RESET=$'\e[0m'
readonly BLUE_BACKGROUND=$'\e[104m'

# misc

VERSION="1.2.2"
update_available=""
readonly FZF_HEADER="rapid-iperf $VERSION 
Bash script tool for running iperf3 network tests with automatic server selection based on latency"


# do not edit below

SPINNER_PID=""
declare REGIONS=("Russia" "Europe" "Asia" "North America" "Latin America" "Oceania" "Africa")
declare MENU_OPTIONS=("Run test (select region)" "Test favourite servers" "Fetch newest iperf lists" "iperf3 params editor" "Quit")

# core

function detect_os {
	source /etc/os-release

	case "$ID" in
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

spinner() {
	local msg="$1"
	while true; do
		for f in ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏; do
			printf "\r%s %s" "$f" "$msg"
			sleep 0.1
		done
	done
}

start_spinner() {
	spinner "$1" &
	SPINNER_PID=$!
}

stop_spinner() {
	if [[ -n "${SPINNER_PID:-}" ]]; then
		kill "$SPINNER_PID" 2>/dev/null || true
		wait "$SPINNER_PID" 2>/dev/null || true
	fi
	SPINNER_PID=""
	printf "\r\033[K"
}

trap 'stop_spinner; exit 130' INT

function check_requirements {
	check_for_updates

	mkdir -p "$IPERF_FOLDER_LOCATION"
	if [[ ! -f "$IPERF_FOLDER_LOCATION/params.txt" ]]; then
cat > "$IPERF_FOLDER_LOCATION/params.txt" << EOU
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


	local required_packages=("jq" "yq" "fping" "iperf3" "curl")
	local missing_packages=()

	os_type=$(detect_os)

	for cmd in "${required_packages[@]}"; do
		if ! command -v "$cmd" &>/dev/null; then
			missing_packages+=("$cmd")
		fi
	done

	if [[ $UI_MODE == fzf ]]; then
		if [[ $(command -v fzf) ]]; then
			UI_MODE=auto
		else
			printf "%s\n" "fzf is not installed. Running in standard mode
			"
			UI_MODE=standard
		fi
	elif [[ $UI_MODE == standard ]]; then
		UI_MODE=standard
	elif [[ $UI_MODE == auto ]]; then
		if [[ $(command -v fzf) ]]; then
			UI_MODE=fzf
		else
			UI_MODE=standard
		fi
	fi

	if ((${#missing_packages[@]})); then
		printf "%s\n" "Following important packages required to install: 
${missing_packages[@]}
Soft dependency: fzf"
		read -r -p "Install important packages? [y/N]: " answer

		if [[ "$answer" =~ ^[Yy] ]]; then
			case "$os_type" in
			debian)
				sudo apt install "${missing_packages[@]}" -y && menu || exit 1
				;;
			rhel)
				sudo dnf install -y "${missing_packages[@]}" && menu || exit 1
				;;
			*)
				echo "Failed to install: Unknown OS. Install requirements manually" || exit 1
				;;
			esac
		else
			echo "Installation rejected. Quiting"
			exit 0
		fi
		if [[ ! $(command -v fzf) ]]; then
			echo -e "You can install ${BLUE_BACKGROUND}fzf${RESET} package to enable modern UI."
		fi
		fetch_iperf
	fi
}



function run_test {
	IPERF_PARAMS=$(awk 'NR==13 {print $0}' "$IPERF_FOLDER_LOCATION/params.txt")
	host=$1
	port=$2
	if timeout $IPERF_TIMEOUT_SEC iperf3 -c "$host" -p "$port" "$IPERF_PARAMS"; then
		found=false
		while IFS='|' read -r fav_host fav_port fav_city fav_country fav_isp; do
			if [[ "$fav_host" == "$host" ]]; then
				found=true
				break
			fi
		done <"$IPERF_FOLDER_LOCATION/favourites.txt"
		if ! $found; then
			read -r -p "Save this server to favourites? [y/N]: " answer

			if [[ "$answer" =~ ^[Yy] ]]; then
				echo "$host|$port|$city|$country|$isp" >>"$IPERF_FOLDER_LOCATION/favourites.txt"
			fi
		fi
	else
		echo "Failed to start iperf3 test."
	fi
	read -n 1 -s -r -p "Press any key to continue ..."

}

function select_favourite {
	case $UI_MODE in
	fzf)
		choose=$({
			while IFS='|' read -r host port city country isp; do
				echo "$host $port $isp ($city, $country)"
			done <"$IPERF_FOLDER_LOCATION/favourites.txt"
			echo "Back"
		} | fzf --header "$FZF_HEADER" --layout=reverse --bind 'esc:abort') || true
		if [[ -z "$choose" || "$choose" == "Back" ]]; then
			echo "back"
			return 0
		fi

		host=$(printf "%s\n" "$choose" | awk '{print $1}')
		port=$(printf "%s\n" "$choose" | awk '{print $2}')
		;;
	*)
		ping_color="\e[104m"
		num=0
		mapfile -t best_ip < <(cat "$IPERF_FOLDER_LOCATION/favourites.txt")
		if [[ "${#best_ip[@]}" == 0 ]]; then
			echo -e "\nError: No favourite servers found. You can add one after starting test\n"
			return 0

		fi
		printf "%b%-5s %-40s %-25s %-20s\e[0m\n" \
			"$ping_color" "" "Host" "City and country" "ISP"
		while IFS='|' read -r host port city country isp; do
			num=$((num + 1))
			printf "%-5s %-40s %-25s %-20s\n" \
				"$num" "$host" "$city, $country" "$isp"
		done < <(printf "%s\n" "${best_ip[@]}")
		read -r -p "Select server number (0 to quit): " input
		selected=${best_ip[$((input - 1))]}
		if [[ $input == 0 ]]; then
			return 0
		fi
		host=$(printf "%s\n" "$selected" | cut -d'|' -f1)
		port=$(printf "%s\n" "$selected" | cut -d'|' -f2)
		;;
	esac

	run_test "$host" "$port"
}

function fetch_iperf {
	start_spinner "Fetching newest iperf servers"
	iperf_global=$IPERF_FOLDER_LOCATION/$IPERF_SERVERS_GLOBAL_FILENAME
	iperf_ru=$IPERF_FOLDER_LOCATION/$IPERF_SERVERS_RU_FILENAME
	if curl --connect-timeout 5 https://export.iperf3serverlist.net/listed_iperf3_servers.json -o "$iperf_global.tmp" >/dev/null 2>&1; then
		iconv -f UTF-8 -t ASCII//TRANSLIT -c "$iperf_global.tmp" >"$iperf_global"
	else
		echo "Failed to reach https://export.iperf3serverlist.net/listed_iperf3_servers.json"
		read -n 1 -s -r -p "Press any key to continue ..."
	fi
	if curl --connect-timeout 5 https://raw.githubusercontent.com/itdoginfo/russian-iperf3-servers/refs/heads/main/list.yml -o "$iperf_ru.tmp" >/dev/null 2>&1; then
		mv "$iperf_ru.tmp" "$iperf_ru"
	else
		echo "Failed to reach https://raw.githubusercontent.com/itdoginfo/russian-iperf3-servers/refs/heads/main/list.yml"
		read -n 1 -s -r -p "Press any key to continue ..."
	fi
	stop_spinner
	return 0
}

function find_best_server {
	cmd=$1
	mapfile -t servers < <(printf "%s\n" "$cmd")
	total=${#servers[@]}

	start_spinner "Scanning $total servers"
	mapfile -t best_ip < <(
		(printf "%s\n" "${servers[@]}" | cut -d'|' -f1 | $FPING_CMD 2>&1 || true) |
			awk '$3 > 0 {print $1, int($3)}' |
			sort -k2 -n
	)
	stop_spinner
	case "$UI_MODE" in
	fzf)
		selected=$(
			while read -r host ping; do
				meta=$(printf "%s\n" "$cmd" | awk -F'|' -v h="$host" '$1==h')
				IFS='|' read -r _ port city country isp <<<"$meta"
				if [[ "$ping" -gt 150 ]]; then
					ping_color="\e[1;31m"
				elif [[ "$ping" -gt 70 ]]; then
					ping_color="\e[1;33m"
				else
					ping_color="\e[1;32m"
				fi
				printf "%-40s %b%-6s\e[0m %-25s %-20s\n" \
					"$host" "$ping_color" "$ping ms" "$city, $country" "$isp"
			done < <(printf "%s\n" "${best_ip[@]}") | fzf --reverse --ansi
		) || exit 0
		if [[ -z "$selected" ]]; then
			menu
			return
		fi

		formatted_ip=$(awk '{print $1}' <<<"$selected")
		best_server=$(grep "^${formatted_ip}|" <<<"$cmd")
		IFS='|' read -r host port city country isp <<<"$best_server"
		;;
	*)
		num=0
		printf "%b%-5s %-40s %-6s %-25s %-30s\e[0m\n" \
			"${BLUE_BACKGROUND}" " " "Host" "Ping" "City and country" "ISP"
		while read -r host ping; do
			meta=$(printf "%s\n" "$cmd" | awk -F'|' -v h="$host" '$1==h')
			IFS='|' read -r _ port city country isp <<<"$meta"
			if [[ "$ping" -gt 150 ]]; then
				ping_color=$PING_COLOR_HIGH
			elif [[ "$ping" -gt 70 ]]; then
				ping_color=$PING_COLOR_MEDIUM
			else
				ping_color=$PING_COLOR_LOW
			fi
			num=$((num + 1))
			printf "%-5s %-40s %b%-6s\e[0m %-25s %-20s\n" \
				"$num" "$host" "$ping_color" "$ping ms" "$city, $country" "$isp"
		done < <(printf "%s\n" "${best_ip[@]}")
		read -r -p "${BLUE_BACKGROUND}Select server number (0 to quit):${RESET} " input
		if [[ $input == 0 ]]; then
			return 0
		fi
		selected=${best_ip[$((input - 1))]}
		host=$(awk '{print $1}' <<<"$selected")
		meta=$(grep -F "${host}|" <<<"$cmd" | head -1)
		IFS='|' read -r _ port city country isp <<<"$meta"
		;;
	esac

	run_test "$host" "$port"

}

function choose_region {
	local iperf_global=$IPERF_SERVERS_GLOBAL_FILE_LOCATION
	local iperf_ru=$IPERF_SERVERS_RU_FILE_LOCATION

	if [[ $UI_MODE == fzf ]]; then
		choose=$(printf "%s\n" "${REGIONS[@]}" | fzf --header "$FZF_HEADER" --layout=reverse)
	else
		select choose in "${REGIONS[@]}" "Back"; do
			if [[ -z $choose ]]; then
				continue
			fi
			break
		done
		if [[ $choose == "Back" ]]; then
			return 0
		fi
	fi
	if [[ $choose == "Russia" ]]; then
		if cmd=$(yq -r '.[] | "\(.address)|\(.port)|\(.City)|RU|\(.Name)"' "$iperf_ru"); then
			find_best_server "$cmd"
		else
			read -n 1 -s -r -p "Fetch servers first. Press any key to continue ..."
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

function params_editor {
	if command -v nano > /dev/null ; then
		nano "$IPERF_FOLDER_LOCATION/params.txt"
	elif command -v vi > /dev/null; then
		vi "$IPERF_FOLDER_LOCATION/params.txt"
	elif command -v vim > /dev/null; then
		vim "$IPERF_FOLDER_LOCATION/params.txt"		
	else 
		echo "Nano or vi not found. Edit it manually at $IPERF_FOLDER_LOCATION/params.txt"
	fi
}

function menu {
	choose=$(printf "%s\n" "${MENU_OPTIONS[@]}" | fzf --header "$FZF_HEADER		$update_available" --layout=reverse)
	case $choose in
	"Run test (select region)")
		choose_region
		;;
	"Test favourite servers")
		select_favourite
		;;
	"Fetch newest iperf lists")
		fetch_iperf
		;;
	"iperf3 params editor")
		params_editor
		;;
	"Quit")
		exit 1
		;;
	*) ;;
	esac
}

function legacy_menu {
	printf "%s\n" "$update_available
	"
	printf "%s\n" "$FZF_HEADER
"
	echo "Current mode $UI_MODE"
	select choose in "${MENU_OPTIONS[@]}"; do
		case $choose in
		"Run test (select region)")
			choose_region
			break
			;;
		"Test favourite servers")
			select_favourite
			break
			;;
		"Fetch newest iperf lists")
			fetch_iperf
			break
			;;
		"iperf3 params editor")
			params_editor
			break
			
			;;
		"Quit")
			exit 1
			;;
		*) ;;
		esac
	done
}

function check_for_updates {
	REPO_URL="https://github.com/lookingglass/rapid-iperf"
	VERSION_FILE="https://raw.githubusercontent.com/lookingglass/rapid-iperf/refs/heads/main/.github/version"
	if ! LATEST_VERSION=$(curl -fsSL  --connect-timeout 1 --max-time 1 "$VERSION_FILE" 2>/dev/null); then
		echo "Failed to check updates"
	else
		if [ "$VERSION" != "$LATEST_VERSION" ]; then
			update_available="Newest version available: $COLOR_GREEN$LATEST_VERSION$RESET - $COLOR_YELLOW$UNDERLINE$REPO_URL$RESET"
		fi
	fi
}

check_requirements
while true; do
	if [[ $UI_MODE == auto ]]; then
		if [[ $(command -v fzf) ]]; then
			UI_MODE=auto
			menu
		fi

	else
		if [[ $UI_MODE == fzf ]]; then
			menu
			if [[ $UI_MODE == standard ]]; then
				legacy_menu
			fi
		else
			UI_MODE=standard
			legacy_menu
		fi
	fi
done
