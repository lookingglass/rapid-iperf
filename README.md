# rapid-iperf
<p align=center>
   <img src="https://i.imgur.com/G8lJttS.png" width="50%">
</p>
<p align="center">
  🚀 <strong>Interactive CLI Bash utility for running iperf3 network tests with automatic servers from public lists</strong>
</p>
<br>


## ❓ What the purpose of this tool?
Initially i struggled a problem finding iperf3 servers. You find some iperf3 servers -> you run a test -> they are too far or just dont work -> repeat. Annoying cycle. I built a plug-and-play solution.

## ⚡ Features
- Automatically downloads iperf3 public servers
- Latency-based iperf3 server selection
- Interactive navigation using `fzf`
- Favourite servers feature

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

## 🚀 Installation & Run

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
- [X] Classic/standard mode (Non-fzf UI mode)

---

## 📦 Dependencies
### Important
* `iperf3` - Network bandwith tool
* `fping` - ICMP check
* `jq` & `yq` - JSON and YAML servers parsing
* `curl` - Fetching iperf3 servers

### Soft dependencies
* `fzf` - Interactive UI

## 🆗 Tested on:
- Ubuntu 24.04
- Fedora 43

## 📋 Notes
This is my first serious open-source development attempt. I still learning and improving my Bash skills. Feedback highly appreciated. Thanks!
