#!/usr/bin/env bash

set -uo pipefail

# ================= CONFIG =====================
TIMEOUT_MS=3500
BATCH_SIZE=8000
PORT_RANGE="1-65535"
ALIVE_FILE="alive_hosts.txt"
PORTS_FILE="open_ports.txt"
NMAP_DIR="nmap_results"


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ---------- dependency check ----------
for cmd in rustscan fping nmap; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo -e "${RED}Error: $cmd not found${NC}"
        exit 1
    fi
done

# ---------- usage ----------
if [[ $# -ne 1 ]]; then
    echo "Usage:"
    echo "  $0 192.168.1.0/24"
    exit 1
fi

SUBNET="$1"

# ---------- prepare ----------
mkdir -p "$NMAP_DIR"
> "$PORTS_FILE"

echo -e "${YELLOW}[*] Discovering alive hosts in $SUBNET...${NC}"

fping -a -q -g --retry=3 -t 2000 "$SUBNET" 2>/dev/null | sort -V | tee "$ALIVE_FILE"

if [[ ! -s "$ALIVE_FILE" ]]; then
    echo -e "${RED}No alive hosts found.${NC}"
    exit 1
fi

echo -e "${GREEN}[+] Alive hosts saved to $ALIVE_FILE${NC}"
echo


echo -e "${YELLOW}[*] Running RustScan on alive hosts...${NC}"
echo

printf "${GREEN}%-18s | %-60s${NC}\n" "IP ADDRESS" "OPEN PORTS"
printf "%-18s-+-%-60s\n" "------------------" "------------------------------------------------------------"

while read -r ip; do

    open_ports=()

    while read -r line; do
        if [[ $line =~ ^Open[[:space:]]+[^:]+:([0-9]+)$ ]]; then
            open_ports+=("${BASH_REMATCH[1]}")
        fi
    done < <(
        rustscan \
            -a "$ip" \
            -r "$PORT_RANGE" \
            --timeout "$TIMEOUT_MS" \
            --batch-size "$BATCH_SIZE" \
            --tries 3 \
            --ulimit 5000 2>/dev/null \
        | grep '^Open ' || true
    )

    if [[ ${#open_ports[@]} -gt 0 ]]; then
        ports=$(IFS=','; echo "${open_ports[*]}")
        printf "%-18s | %-60s\n" "$ip" "$ports"
        echo "$ip $ports" >> "$PORTS_FILE"
    else
        printf "%-18s | %-60s\n" "$ip" "None"
    fi

done < "$ALIVE_FILE"

echo
echo -e "${GREEN}[+] Open ports saved to $PORTS_FILE${NC}"
echo


echo -e "${YELLOW}[*] Starting Nmap detailed scans...${NC}"
echo

while read -r line; do

    ip=$(echo "$line" | awk '{print $1}')
    ports=$(echo "$line" | awk '{print $2}')

    if [[ -z "$ports" ]] || [[ "$ports" == "None" ]]; then
        continue
    fi

    echo -e "${YELLOW}[*] Scanning $ip on ports: $ports${NC}"

    nmap -Pn -sV  --script=vuln -p "$ports" "$ip" -oN "$NMAP_DIR/$ip.txt" >/dev/null 2>&1

    echo -e "${GREEN}[+] Saved: $NMAP_DIR/$ip.txt${NC}"
    echo

done < "$PORTS_FILE"

echo -e "${GREEN}Recon Pipeline Complete.${NC}"
