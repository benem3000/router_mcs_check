#!/bin/bash

# ==============================================================================
# Wireless MCS Discovery & SSID Tool
# Description: Tiered hardware identification (WSC > Gateway ARP > OUI > API).
# Usage: sudo ./routermcs.sh [-d | --debug] [-v | --verbose]
# ==============================================================================

# --- COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- INITIALIZATION ---
REAL_USER=${SUDO_USER:-$USER}
DEBUG=false
VERBOSE=false
FULL_LOG="routermcs_full.log"
TEMP_LOG=$(mktemp)
ISP_TEMP=$(mktemp)

for arg in "$@"; do
    case $arg in
        -d|--debug)   DEBUG=true ;;
        -v|--verbose) VERBOSE=true ;;
    esac
done

if [[ "$DEBUG" == "true" && "$VERBOSE" == "true" ]]; then
    echo "--- FULL SESSION START: $(date) ---" > "$FULL_LOG"
    chown "$REAL_USER:$REAL_USER" "$FULL_LOG" 2>/dev/null
fi

log_cmd() {
    local label="$1"
    local cmd="$2"
    if [[ "$DEBUG" == "true" && "$VERBOSE" == "true" ]]; then
        echo -e "${YELLOW}[EXEC] $label: $cmd${NC}" | tee -a "$FULL_LOG"
        eval "$cmd" 2>&1 | tee -a "$FULL_LOG"
    elif [[ "$VERBOSE" == "true" ]]; then
        echo -e "${YELLOW}[EXEC] $label${NC}"
        eval "$cmd"
    else
        eval "$cmd" > /dev/null 2>&1
    fi
}

[[ $EUID -ne 0 ]] && { echo -e "${YELLOW}Root required. Requesting sudo...${NC}"; sudo -v || exit 1; exec sudo "$0" "$@"; }

for cmd in iw iwmon awk lspci lsusb traceroute curl ethtool; do
    command -v $cmd &> /dev/null || { echo -e "${RED}ERROR: '$cmd' is missing.${NC}"; exit 1; }
done

clear
echo -e "${BLUE}-------------------------------------------------------${NC}"
echo -e "${BLUE}        Wireless MCS Discovery & SSID Tool             ${NC}"
echo -e "${BLUE}-------------------------------------------------------${NC}"

# --- INTERFACE DISCOVERY ---
mapfile -t iw_out < <(iw dev)
declare -A phy_map
phys=()
current_phy=""

for line in "${iw_out[@]}"; do
    if [[ $line =~ phy#([0-9]+) ]]; then
        current_phy="phy${BASH_REMATCH[1]}"
        phys+=("$current_phy")
    elif [[ $line =~ Interface\ ([^[:space:]]+) ]]; then
        wlan="${BASH_REMATCH[1]}"
        phy_map["$current_phy"]+="$wlan "
    fi
done

[[ ${#phys[@]} -eq 0 ]] && { echo -e "${RED}ERROR: No wireless hardware found.${NC}"; exit 1; }

# --- STEP 1: PHY & CARD ID ---
echo -e "\n${GREEN}Step 1: Select Physical Interface${NC}"
phy_display=()
for p in "${phys[@]}"; do phy_display+=("$p (Handles: ${phy_map[$p]:-none})"); done
PS3="Selection (Enter 1-${#phys[@]}): "
while true; do
    select choice in "${phy_display[@]}"; do
        if [[ -n "$choice" ]]; then PHY=$(echo "$choice" | awk '{print $1}'); break 2;
        else echo -e "\n${YELLOW}>>> Warning: Invalid selection.${NC}"; break; fi
    done
done

TARGET_WLAN=(${phy_map[$PHY]})
BUS_ID=$(ethtool -i "${TARGET_WLAN[0]}" 2>/dev/null | grep "bus-info" | awk '{print $2}')
if [[ "$BUS_ID" =~ [0-9a-fA-F]{4}: ]]; then
    LOCAL_CARD=$(lspci -s "$BUS_ID" | cut -d' ' -f4-)
else
    LOCAL_CARD=$(lspci | grep -i wireless | head -n 1 | cut -d' ' -f4-)
    [[ -z "$LOCAL_CARD" ]] && LOCAL_CARD=$(lsusb | grep -i wireless | head -n 1 | cut -d' ' -f7-)
fi
echo -e "[+] Local Card: ${BLUE}${LOCAL_CARD:-Generic Adapter}${NC}"

# --- STEPS 2-5 ---
echo -e "\n${GREEN}Step 2: Select Wireless Interface${NC}"
filtered_wlans=(${phy_map[$PHY]})
PS3="Selection (Enter 1-${#filtered_wlans[@]}): "
while true; do
    select WLAN in "${filtered_wlans[@]}"; do
        [[ -n "$WLAN" ]] && break 2 || { echo -e "\n${YELLOW}>>> Warning: Invalid selection.${NC}"; break; }
    done
done

CURRENT_SSID=$(iw dev "$WLAN" link | grep "SSID:" | awk '{print $2}')
echo -e "\n${GREEN}Step 3: Choose Reporting Scope${NC}"
if [ -z "$CURRENT_SSID" ]; then
    SCAN_MODE="All"
else
    options_scope=("Current SSID only ($CURRENT_SSID)" "All Networks")
    select opt in "${options_scope[@]}"; do
        if [[ -n "$opt" ]]; then
            [[ $REPLY -eq 1 ]] && { SCAN_MODE="Single"; TARGET_SSID="$CURRENT_SSID"; } || SCAN_MODE="All"
            break 2
        fi
        break
    done
fi

echo -e "\n${GREEN}Step 4: Select Scan Duration${NC}"
options_dur=("Quick Scan (10s)" "Full Scan (30s)")
select dur_choice in "${options_dur[@]}"; do
    [[ -n "$dur_choice" ]] && { [[ $REPLY -eq 1 ]] && DURATION=10 || DURATION=30; break 2; } || break
done

echo -e "\n${GREEN}Step 5: Privacy Settings${NC}"
options_privacy=("Censor SSID" "Show Full SSID")
select choice in "${options_privacy[@]}"; do
    [[ -n "$choice" ]] && { [[ $REPLY -eq 1 ]] && CENSOR_FLAG="true" || CENSOR_FLAG="false"; break 2; } || break
done

# --- CLEANUP ---
CLEANED_UP=false
cleanup() {
    if [[ "$CLEANED_UP" == "true" ]]; then return; fi
    CLEANED_UP=true
    local exit_code=$?
    echo -e "\n${YELLOW}[*] Cleanup: Verifying background tasks and files...${NC}"
    if [[ "$DEBUG" == "true" && "$VERBOSE" == "false" ]]; then
        cp "$TEMP_LOG" "raw_capture.log"
        chown "$REAL_USER:$REAL_USER" "raw_capture.log" 2>/dev/null
    fi
    [[ -n "$MON_PID" ]] && kill "$MON_PID" 2>/dev/null && echo -e "${GREEN}    [OK] Monitor stopped.${NC}"
    rm -f "$TEMP_LOG" "$ISP_TEMP" && echo -e "${GREEN}    [OK] Temp logs removed.${NC}"
    echo -e "${GREEN}[*] Cleanup verified. Exiting.${NC}"
    exit $exit_code
}
trap cleanup EXIT INT TERM

# --- EXECUTION ---
echo -e "\n${BLUE}[1/3] Initializing capture on $PHY...${NC}"
if [[ "$DEBUG" == "true" && "$VERBOSE" == "true" ]]; then
    iwmon -i "$PHY" | tee -a "$FULL_LOG" > "$TEMP_LOG" 2>&1 &
else
    iwmon -i "$PHY" > "$TEMP_LOG" 2>&1 &
fi
MON_PID=$!
sleep 1

# ISP Identification
ISP_NAME="Unknown"
if [[ -n "$CURRENT_SSID" ]]; then
    echo -e "${BLUE}[*] Identifying ISP via Gateway Traceroute...${NC}"
    ISP_CMD="traceroute -m 8 -q 1 8.8.8.8"
    log_cmd "ISP Traceroute" "$ISP_CMD"
    (eval "$ISP_CMD" 2>&1 | awk '/ms/ && $2 ~ /[a-zA-Z]/ {n=split($2,a,"."); if(n>1) print a[n-1]"."a[n]}' | head -n 1 > "$ISP_TEMP") &
fi

echo -e "${BLUE}[2/3] Triggering scan on $WLAN...${NC}"
log_cmd "Hardware Scan Trigger" "iw dev $WLAN scan"

for ((i=DURATION-1; i>0; i--)); do printf "\r[*] Capturing management frames... %2d seconds remaining " $i; sleep 1; done
echo -e "\r[*] Capture complete! Processing data...                "
kill $MON_PID 2>/dev/null

# Tier 2 Enrichment
ROUTER_MAC_ENRICHED="Unknown"
GW_IP=$(ip route show default | awk '/default/ {print $3; exit}')
if [[ -n "$GW_IP" ]]; then
    ROUTER_MAC_ENRICHED=$(ip neighbor show "$GW_IP" | awk '{print $5; exit}')
fi
[[ -s "$ISP_TEMP" ]] && ISP_NAME=$(cat "$ISP_TEMP")

# --- RESULTS ---
echo -e "\n${BLUE}[3/3] Analysis Results (${SCAN_MODE})${NC}"
echo -e "${BLUE}Hardware: ${NC}${LOCAL_CARD}"
[[ -n "$CURRENT_SSID" ]] && echo -e "${BLUE}ISP:      ${NC}${ISP_NAME:-Undetermined}"
echo "--------------------------------------------------------------------------------------------------------------------------------"
printf "${YELLOW}%-32s | %-12s | %-18s | %-12s | %-12s${NC}\n" "SSID" "BASIC MCS" "VENDOR" "MODEL" "TIER"
echo "--------------------------------------------------------------------------------------------------------------------------------"

# --- TIERED PARSING ---
awk -v mode="$SCAN_MODE" -v target="$TARGET_SSID" -v do_censor="$CENSOR_FLAG" -v enrich_mac="$ROUTER_MAC_ENRICHED" '
BEGIN {
    oui["98:da:c4"]="TP-Link"; oui["00:14:6c"]="Netgear"; oui["10:36:aa"]="Technicolor";
    oui["08:b4:d2"]="Ubiquiti"; oui["0c:39:3d"]="Eero"; oui["08:02:8e"]="NETGEAR";
    oui["66:67:72"]="TP-Link (Mesh)"; oui["5c:e9:31"]="TP-Link";
}

function truncate(str, len) {
    if (length(str) > len) return substr(str, 1, len-3) "..."
    return str
}

function save_entry() {
    # CRITICAL: Only save if we found an actual SSID in this block
    if (ssid_to_save == "") return
    if (mode == "Single" && ssid_to_save != target) return

    if (do_censor == "true") {
        len = length(ssid_to_save); if (len > 2) {
            stars = ""; for (i = 2; i < len; i++) stars = stars "*";
            final_name = substr(ssid_to_save, 1, 1) stars substr(ssid_to_save, len, 1);
        } else { final_name = ssid_to_save; }
    } else { final_name = ssid_to_save; }

    source = "None"; v_final = "Unknown"; m_final = "N/A"
    if (manuf != "") {
        v_final = manuf; m_final = (m_name != "" ? m_name : (m_num != "" ? m_num : "N/A")); source = "WSC (T1)"
    } else {
        check_mac = (ssid_to_save == target && enrich_mac != "Unknown") ? enrich_mac : mac_addr
        prefix = tolower(substr(check_mac, 1, 8))
        if (prefix in oui) { v_final = oui[prefix]; source = "OUI (T3)"; }
        else if (check_mac != "" && check_mac != "Unknown") {
            cmd = "curl -s --connect-timeout 2 https://api.macvendors.com/" check_mac
            if ((cmd | getline online_v) > 0 && online_v != "" && online_v !~ /errors|Not Found/) {
                v_final = online_v; source = "API (T4)";
            }
            close(cmd);
        }
    }
    mcs_str = (found_mcs) ? sprintf("MCS %d-%d", min_mcs, max_mcs) : "None"

    # Store result, prioritizing T1/T3/T4 over "None"
    if (!results[final_name] || (source != "None" && results[final_name] ~ /None/)) {
        results[final_name] = sprintf("%-32s | %-12s | %-18s | %-12s | %-12s",
            truncate(final_name, 32),
            mcs_str,
            truncate(v_final, 18),
            truncate(m_final, 12),
            source)
    }
    # Reset ssid_to_save after commit to prevent bleed into SSID-less packets
    ssid_to_save = ""
}

# New block reset on BSSID, BSS, or Source Address (TA)
/BSSID / || /^BSS / || /Address 2 \(TA\):/ {
    save_entry()
    found_mcs = 0; min_mcs = 999; max_mcs = -1; manuf = ""; m_name = ""; m_num = ""; mac_addr = "";
    if ($0 ~ /Address 2 \(TA\):/) mac_addr = $NF
    else if ($1 == "BSSID") mac_addr = $2
    else if ($1 == "BSS") { mac_addr = $2; sub(/\(.*/, "", mac_addr); }
    gsub(/[[:space:]]/, "", mac_addr);
}

/^[[:space:]]*SSID: / {
    raw = $0; sub(/.*SSID: /, "", raw); gsub(/[[:space:]]+$/, "", raw);
    ssid_to_save = raw;
}

/Basic MCS set: MCS [0-9]+/ {
    found_mcs = 1; v = $NF;
    if (v ~ /^[0-9]+$/) { if (v < min_mcs) min_mcs = v; if (v > max_mcs) max_mcs = v; }
}

/Manufacturer: / { sub(/.*Manufacturer: /, "", $0); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); manuf = $0; }
/Model Name: /   { sub(/.*Model Name: /, "", $0); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); m_name = $0; }
/Model Number: / { sub(/.*Model Number: /, "", $0); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); m_num = $0; }

END { save_entry(); for (s in results) print results[s] }
' "$TEMP_LOG" | sort
