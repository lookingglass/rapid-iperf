# rapid-iperf
<p align=center>
   <img src="https://i.imgur.com/kFyQACA.jpeg" width="70%">
</p>
<p align="center">
  🚀 <strong>Interactive Bash utility for running iperf3 network tests with automatic servers from public lists</strong>
</p>
<br>


## ❓ Purpose
You find some iperf3 servers -> you run a test -> they are too far or just dont work -> repeat. Annoying cycle? Use this tool.

<p align="center">

| File | Mode | Description |
|---|---|---|
| `rapid-iperf.sh` | TUI + CLI | Full version. Launches the TUI when run without arguments |
| `rapid-iperf-CLI.sh` | CLI only | Lightweight CLI-only version. Run it to see the available options |

</p>

## ⚡ Features
- Automatically downloads iperf3 public servers
- Latency-based iperf3 server selection
- Interactive TUI (arrow navigation) + CLI modes
- Managing direction (Upload/Download/Both)
- Favourite servers feature
- Iperf3 params editor
- Automatic install of dependencies

## 🌍 Available regions
- Russia
- Europe
- Asia
- North America
- Latin America
- Oceania
- Africa

## 🧠 How it works?
This tool automatically downloads and parses public iperf3 servers from:
1. https://github.com/itdoginfo/russian-iperf3-servers
2. https://iperf3serverlist.net
---

## 🚀 Usage

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


## 📝 Todo
- [x] Region selection
- [x] Automatic install of dependencies
- [X] Favourite servers
- [X] Available servers selection UI
- [X] Classic/standard mode (Non-fzf UI mode) (upd: fzf mode is deprecated, replaced with own UI)
- [X] New UI
- [X] CLI mode

---

## 📦 Dependencies
### Important
* `iperf3` - Network bandwith tool
* `fping` - ICMP check
* `jq` & `yq` - JSON and YAML servers parsing
* `curl` - Fetching iperf3 servers


## 🆗 Tested on:

* ![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu_24.04-E95420?logo=ubuntu&logoColor=white)<br>
* ![Fedora 43](https://img.shields.io/badge/Fedora_43-51A2DA?logo=fedora&logoColor=white)<br>
* ![AlmaLinux 9.6](https://img.shields.io/badge/AlmaLinux_9.6-0F4266?logo=almalinux&logoColor=white)<br>

