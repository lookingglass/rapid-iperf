# rapid-iperf

## Major beta features
- New TUI (without fzf dependency)
- CLI mode 
- Test direction management (Upload/Download/Both)


## CLI usage
```
rapid-iperf.sh Usage:

rapid-iperf.sh --help                Display help

rapid-iperf.sh --list-regions        Display list of regions
rapid-iperf.sh --list-directions     Display list of test directions
rapid-iperf.sh --region=[region]     Run test in a specific region
rapid-iperf.sh --count=<count>       Count of servers to test
rapid-iperf.sh --direction=<dir>     Upload | Download | Both
rapid-iperf.sh --format=json         Output results as JSON
rapid-iperf.sh --file=<path>         Send JSON output to file instead of stdout

```
### Regions
```
Russia | RU
Europe | EU
North America | NA
South America | Latin America | SA
Asia | AS
Africa | AC
Australia | Oceania | AU | OC
```
## Dependencies
```
    iperf3 - Network bandwith tool
    fping - ICMP check
    jq & yq - JSON and YAML servers parsing
    curl - Fetching iperf3 servers
