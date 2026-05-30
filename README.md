# rapid-iperf
Interactive CLI Bash utility for running iperf3 network tests with automatic servers from public lists

## Features
- Automatically downloads iperf3 public servers
- Latency-based iperf3 server selection
- Interactive navigation using `fzf`
- Favourite servers feature

## Available regions
- Russia
- Europe
- Asia
- North America
- Latin America
- Oceania
- Africa

## How it works?
This tool automatically downloads and parses public iperf3 servers from:
1. https://github.com/itdoginfo/russian-iperf3-servers
2. https://iperf3serverlist.net
---

## Installation & Run

1. **Clone repository:**
   ```bash
   git clone https://github.com/lookingglass/rapid-iperf
   cd rapid-iperf
   ```

2. **Make script executable:**
   ```bash
   chmod +x rapid-iperf.sh
   ```

3. **Run tool:**
   ```bash
   ./rapid-iperf.sh
   ```

---

## Todo
- [x] Region selection
- [x] Automatic install of dependencies
- [X] Favourite servers
- [X] Fallback server feature -> Available servers selection UI
- [X] Classic/standard mode (Non-fzf UI)

---

## Dependencies
* `iperf3` - Network bandwith tool
* `fping` - ICMP check
* `jq` & `yq` - JSON and YAML servers parsing
* `curl` - Fetching iperf3 servers

# Soft dependencies
* `fzf` - Interactive UI

## Notes
Dependencies will install if you are running Debian/Ubuntu or RHEL/Fedora. Other cases requires manual installation
Still WIP
