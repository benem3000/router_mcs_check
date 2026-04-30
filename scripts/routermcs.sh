#!/bin/bash

# ==============================================================================
# Wireless MCS Discovery & SSID Tool
# Usage: sudo ./routermcs.sh [-d | --debug] [-v | --verbose] [-c | --csv]
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
CSV_OUT=false
FULL_LOG="routermcs_full.log"
TEMP_LOG=$(mktemp)
ISP_TEMP=$(mktemp)

for arg in "$@"; do
    case $arg in
        -d|--debug)   DEBUG=true ;;
        -v|--verbose) VERBOSE=true ;;
        -c|--csv)     CSV_OUT=true ;;
    esac
done

# --- COMPREHENSIVE LOGGING SETUP ---
if [[ "$DEBUG" == "true" ]]; then
    echo -e "\n--- FULL SESSION START: $(date) ---" >> "$FULL_LOG"
    chown "$REAL_USER:$REAL_USER" "$FULL_LOG" 2>/dev/null

    exec > >(tee -a "$FULL_LOG") 2>&1

    echo -e "${YELLOW}[*] Debug Mode Enabled: Full bash trace and log generation active.${NC}"
    set -x
elif [[ "$VERBOSE" == "true" ]]; then
    echo -e "${YELLOW}[*] Verbose Mode Enabled: Logging command outputs to console.${NC}"
fi

[[ $EUID -ne 0 ]] && { echo -e "${YELLOW}Root required. Requesting sudo...${NC}"; sudo -v || exit 1; exec sudo "$0" "$@"; }

for cmd in iw iwmon awk lspci lsusb traceroute curl ethtool; do
    command -v $cmd &> /dev/null || { echo -e "${RED}ERROR: '$cmd' is missing.${NC}"; exit 1; }
done

[[ "$DEBUG" == "true" ]] && set +x
clear
echo -e "${BLUE}-------------------------------------------------------${NC}"
echo -e "${BLUE}        Wireless MCS Discovery & SSID Tool             ${NC}"
echo -e "${BLUE}-------------------------------------------------------${NC}"
[[ "$DEBUG" == "true" ]] && set -x

mapfile -t iw_out < <(iw dev)
declare -A phy_map
phys=()
current_phy=""

for line in "${iw_out[@]}"; do
    if [[ $line =~ phy
        current_phy="phy${BASH_REMATCH[1]}"
        phys+=("$current_phy")
    elif [[ $line =~ Interface\ ([^[:space:]]+) ]]; then
        wlan="${BASH_REMATCH[1]}"
        phy_map["$current_phy"]+="$wlan "
    fi
done

[[ ${#phys[@]} -eq 0 ]] && { echo -e "${RED}ERROR: No wireless hardware found.${NC}"; exit 1; }

[[ "$DEBUG" == "true" ]] && set +x
declare -A phy_cards
phy_display=()
for p in "${phys[@]}"; do
    wlan_array=(${phy_map[$p]})
    first_wlan=${wlan_array[0]}
    card_name="Generic Adapter"
    if [[ -n "$first_wlan" ]]; then
        BUS_ID=$(ethtool -i "$first_wlan" 2>/dev/null | grep "bus-info" | awk '{print $2}')
        if [[ "$BUS_ID" =~ [0-9a-fA-F]{4}: ]]; then
            card_name=$(lspci -s "$BUS_ID" | cut -d' ' -f4-)
        else
            card_name=$(lspci | grep -i wireless | head -n 1 | cut -d' ' -f4-)
            [[ -z "$card_name" ]] && card_name=$(lsusb | grep -i wireless | head -n 1 | cut -d' ' -f7-)
        fi
    fi
    phy_cards[$p]="$card_name"
    phy_display+=("$p - $card_name (Handles: ${phy_map[$p]:-none})")
done
[[ "$DEBUG" == "true" ]] && set -x

[[ "$DEBUG" == "true" ]] && set +x
echo -e "\n${GREEN}[1/5] Select Physical Interface${NC}"
PS3="Selection (Enter 1-${#phys[@]}): "
while true; do
    select choice in "${phy_display[@]}"; do
        if [[ -n "$choice" ]]; then
            [[ "$DEBUG" == "true" ]] && echo "[USER INPUT] Step 1 Selection ($REPLY): $choice" >> "$FULL_LOG"
            PHY=$(echo "$choice" | awk '{print $1}')
            LOCAL_CARD="${phy_cards[$PHY]}"
            break 2
        else
            [[ "$DEBUG" == "true" ]] && echo "[USER INPUT] Step 1 Invalid Selection: $REPLY" >> "$FULL_LOG"
            echo -e "\n${YELLOW}>>> Warning: Invalid selection.${NC}"
            break
        fi
    done
done
[[ "$DEBUG" == "true" ]] && set -x

[[ "$DEBUG" == "true" ]] && set +x
echo -e "\n${GREEN}[2/5] Select Wireless Interface${NC}"
filtered_wlans=(${phy_map[$PHY]})
PS3="Selection (Enter 1-${#filtered_wlans[@]}): "
while true; do
    select WLAN in "${filtered_wlans[@]}"; do
        if [[ -n "$WLAN" ]]; then
            [[ "$DEBUG" == "true" ]] && echo "[USER INPUT] Step 2 Selection ($REPLY): $WLAN" >> "$FULL_LOG"
            break 2
        else
            [[ "$DEBUG" == "true" ]] && echo "[USER INPUT] Step 2 Invalid Selection: $REPLY" >> "$FULL_LOG"
            echo -e "\n${YELLOW}>>> Warning: Invalid selection.${NC}"
            break
        fi
    done
done
[[ "$DEBUG" == "true" ]] && set -x

CURRENT_SSID=$(iw dev "$WLAN" link | grep "SSID:" | awk '{print $2}')

[[ "$DEBUG" == "true" ]] && set +x
echo -e "\n${GREEN}[3/5] Choose Reporting Scope${NC}"
if [ -z "$CURRENT_SSID" ]; then
    SCAN_MODE="All"
    [[ "$DEBUG" == "true" ]] && echo "[USER INPUT] Step 3 Auto-Selected (No current SSID): All" >> "$FULL_LOG"
else
    options_scope=("Current SSID only ($CURRENT_SSID)" "All Networks")
    PS3="Selection (Enter 1-${#options_scope[@]}): "
    select opt in "${options_scope[@]}"; do
        if [[ -n "$opt" ]]; then
            [[ "$DEBUG" == "true" ]] && echo "[USER INPUT] Step 3 Selection ($REPLY): $opt" >> "$FULL_LOG"
            [[ $REPLY -eq 1 ]] && { SCAN_MODE="Single"; TARGET_SSID="$CURRENT_SSID"; } || SCAN_MODE="All"
            break 2
        fi
        break
    done
fi

echo -e "\n${GREEN}[4/5] Select Scan Duration${NC}"
options_dur=("Quick Scan (10s)" "Full Scan (30s)")
PS3="Selection (Enter 1-${#options_dur[@]}): "
select dur_choice in "${options_dur[@]}"; do
    if [[ -n "$dur_choice" ]]; then
        [[ "$DEBUG" == "true" ]] && echo "[USER INPUT] Step 4 Selection ($REPLY): $dur_choice" >> "$FULL_LOG"
        [[ $REPLY -eq 1 ]] && DURATION=10 || DURATION=30
        break 2
    fi
    break
done

echo -e "\n${GREEN}[5/5] Privacy Setting${NC}"
options_privacy=("Censor SSID" "Show Full SSID")
PS3="Selection (Enter 1-${#options_privacy[@]}): "
select choice in "${options_privacy[@]}"; do
    if [[ -n "$choice" ]]; then
        [[ "$DEBUG" == "true" ]] && echo "[USER INPUT] Step 5 Selection ($REPLY): $choice" >> "$FULL_LOG"
        [[ $REPLY -eq 1 ]] && CENSOR_FLAG="true" || CENSOR_FLAG="false"
        break 2
    fi
    break
done
[[ "$DEBUG" == "true" ]] && set -x
echo ""

CLEANED_UP=false
cleanup() {
    [[ "$DEBUG" == "true" ]] && set +x
    if [[ "$CLEANED_UP" == "true" ]]; then return; fi
    CLEANED_UP=true
    local exit_code=$?
    echo -e "\n${YELLOW}[*] Cleanup: Verifying background tasks and files...${NC}"
    if [[ "$DEBUG" == "true" ]]; then
        cp "$TEMP_LOG" "raw_capture.log"
        chown "$REAL_USER:$REAL_USER" "raw_capture.log" 2>/dev/null
    fi
    [[ -n "$MON_PID" ]] && kill "$MON_PID" 2>/dev/null && echo -e "${GREEN}    [OK] Monitor stopped.${NC}"
    rm -f "$TEMP_LOG" "$ISP_TEMP" && echo -e "${GREEN}    [OK] Temp logs removed.${NC}"
    echo -e "${GREEN}[*] Cleanup verified. Exiting.${NC}"
    exit $exit_code
}
trap cleanup EXIT INT TERM

echo -e "${BLUE}[1/6] Initializing capture on $PHY...${NC}"
iwmon -i "$PHY" > "$TEMP_LOG" 2>&1 &
MON_PID=$!
sleep 1

ISP_NAME="Unknown"
if [[ -n "$CURRENT_SSID" ]]; then
    echo -e "${BLUE}[2/6] Identifying ISP via Gateway Traceroute...${NC}"
    ISP_CMD="traceroute -m 8 -q 1 8.8.8.8"

    [[ "$DEBUG" == "false" && "$VERBOSE" == "true" ]] && echo -e "${YELLOW}[EXEC] ISP Traceroute: $ISP_CMD${NC}"

    if [[ "$VERBOSE" == "true" || "$DEBUG" == "true" ]]; then
        (eval "$ISP_CMD" 2>&1 | tee /dev/stderr | awk '/ms/ && $2 ~ /[a-zA-Z]/ {n=split($2,a,"."); if(n>1) print a[n-1]"."a[n]}' | head -n 1 > "$ISP_TEMP") &
    else
        (eval "$ISP_CMD" 2>&1 | awk '/ms/ && $2 ~ /[a-zA-Z]/ {n=split($2,a,"."); if(n>1) print a[n-1]"."a[n]}' | head -n 1 > "$ISP_TEMP") &
    fi
else
    echo -e "${BLUE}[2/6] Identifying ISP via Gateway Traceroute... (Skipped, no active connection)${NC}"
fi

echo -e "${BLUE}[3/6] Triggering scan on $WLAN...${NC}"
SCAN_CMD="iw dev $WLAN scan"
[[ "$DEBUG" == "false" && "$VERBOSE" == "true" ]] && echo -e "${YELLOW}[EXEC] Hardware Scan Trigger: $SCAN_CMD${NC}"

if [[ "$VERBOSE" == "true" || "$DEBUG" == "true" ]]; then
    eval "$SCAN_CMD"
else
    eval "$SCAN_CMD" >/dev/null 2>&1
fi

[[ "$DEBUG" == "true" ]] && set +x
for ((i=DURATION; i>=0; i--)); do
    printf "\r${BLUE}[4/6] Capturing management frames... %2d seconds remaining ${NC}" "$i"
    [[ $i -gt 0 ]] && sleep 1
done
printf "\r\033[K${BLUE}[4/6] Capture complete! ${NC}\n"
[[ "$DEBUG" == "true" ]] && set -x
kill $MON_PID 2>/dev/null

echo -e "${BLUE}[5/6] Compiling results...${NC}"

ROUTER_MAC_ENRICHED="Unknown"
GW_IP=$(ip route show default | awk '/default/ {print $3; exit}')
if [[ -n "$GW_IP" ]]; then
    ROUTER_MAC_ENRICHED=$(ip neighbor show "$GW_IP" | awk '{print $5; exit}')
fi
[[ -s "$ISP_TEMP" ]] && ISP_NAME=$(cat "$ISP_TEMP")

# --- RESULTS ---
[[ "$DEBUG" == "true" ]] && set +x

PARSED_RESULTS=$(awk -v mode="$SCAN_MODE" -v target="$TARGET_SSID" -v do_censor="$CENSOR_FLAG" -v enrich_mac="$ROUTER_MAC_ENRICHED" -v current_ssid="$CURRENT_SSID" '
BEGIN {
    oui["98:da:c4"]="TP-Link"; oui["00:14:6c"]="Netgear"; oui["10:36:aa"]="Technicolor";
    oui["08:b4:d2"]="Ubiquiti"; oui["0c:39:3d"]="Eero"; oui["08:02:8e"]="NETGEAR";
    oui["5c:e9:31"]="TP-Link";
}

function hex2dec(h) {
    hex_str = "0123456789abcdef";
    h1 = index(hex_str, tolower(substr(h, 1, 1))) - 1;
    h2 = index(hex_str, tolower(substr(h, 2, 1))) - 1;
    return (h1 * 16) + h2;
}

function to_universal_mac(mac) {
    first_octet = substr(mac, 1, 2);
    dec = hex2dec(first_octet);

    is_local = int(dec / 2) % 2;
    if (is_local == 1) {
        dec = dec - 2;
        hex_str = "0123456789abcdef";
        new_h1 = substr(hex_str, int(dec / 16) + 1, 1);
        new_h2 = substr(hex_str, (dec % 16) + 1, 1);
        return new_h1 new_h2 substr(mac, 3);
    }
    return mac;
}

function truncate(str, len) {
    if (length(str) > len) return substr(str, 1, len-3) "...";
    return str;
}

function save_entry() {
    if (ssid_to_save == "") return;
    if (mode == "Single" && ssid_to_save != target) return;

    if (do_censor == "true") {
        len = length(ssid_to_save); if (len > 2) {
            stars = ""; for (i = 2; i < len; i++) stars = stars "*";
            final_name = substr(ssid_to_save, 1, 1) stars substr(ssid_to_save, len, 1);
        } else { final_name = ssid_to_save; }
    } else { final_name = ssid_to_save; }

    v_final = "Unknown";

    if (manuf != "") {
        v_final = manuf;
    } else {
        check_mac = (ssid_to_save == current_ssid && enrich_mac != "Unknown") ? enrich_mac : mac_addr;
        univ_mac = to_universal_mac(check_mac);
        prefix = tolower(substr(univ_mac, 1, 8));

        if (prefix in oui) {
            v_final = oui[prefix];
        }
        else if (univ_mac != "" && univ_mac != "Unknown") {
            cmd = "curl -s --connect-timeout 2 https://api.macvendors.com/" univ_mac;
            if ((cmd | getline online_v) > 0 && online_v != "" && online_v !~ /errors|Not Found/) {
                v_final = online_v;
            }
            close(cmd);
        }
    }

    mcs_str = (found_mcs) ? sprintf("MCS %d-%d", min_mcs, max_mcs) : "None";
    m_name_final = (m_name != "") ? m_name : "N/A";
    m_num_final = (m_num != "") ? m_num : "N/A";

    # Enclose variables in pipe structure for Markdown formatting
    if (!results[final_name] || (results[final_name] ~ /Unknown/ && v_final != "Unknown")) {
        results[final_name] = sprintf("| %-32s | %-12s | %-18s | %-16s | %-16s |",
            truncate(final_name, 32),
            mcs_str,
            truncate(v_final, 18),
            truncate(m_name_final, 16),
            truncate(m_num_final, 16));
    }
    ssid_to_save = "";
}

/BSSID / || /^BSS / || /Address 2 \(TA\):/ {
    save_entry();
    found_mcs = 0; min_mcs = 999; max_mcs = -1; manuf = ""; m_name = ""; m_num = ""; mac_addr = "";
    if ($0 ~ /Address 2 \(TA\):/) mac_addr = $NF;
    else if ($1 == "BSSID") mac_addr = $2;
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

END { save_entry(); for (s in results) print results[s]; }
' "$TEMP_LOG" | sort)

echo -e "${BLUE}[6/6] Finished! (${SCAN_MODE})${NC}"

echo '```'

echo -e "${BLUE}Hardware: ${NC}${LOCAL_CARD}"
[[ -n "$CURRENT_SSID" ]] && echo -e "${BLUE}ISP:      ${NC}${ISP_NAME:-Undetermined}"

echo "--------------------------------------------------------------------------------------------------------------"
printf "%-32s | %-12s | %-18s | %-16s | %-16s\n" "SSID" "BASIC MCS" "VENDOR" "MODEL NAME" "MODEL NUM"
echo "--------------------------------------------------------------------------------------------------------------"
echo "$PARSED_RESULTS"
echo '```'

# CSV Export Routine
if [[ "$CSV_OUT" == "true" ]]; then
    echo "SSID,BASIC_MCS,VENDOR,MODEL_NAME,MODEL_NUM" > "routermcs_results.csv"
    echo "$PARSED_RESULTS" | awk -F'|' '{
        # Trim leading and trailing spaces from the Markdown columns
        gsub(/^[ \t]+|[ \t]+$/, "", $2);
        gsub(/^[ \t]+|[ \t]+$/, "", $3);
        gsub(/^[ \t]+|[ \t]+$/, "", $4);
        gsub(/^[ \t]+|[ \t]+$/, "", $5);
        gsub(/^[ \t]+|[ \t]+$/, "", $6);
        # Print only lines that actually have data
        if ($2 != "") print $2","$3","$4","$5","$6
    }' >> "routermcs_results.csv"
    chown "$REAL_USER:$REAL_USER" "routermcs_results.csv" 2>/dev/null
    echo -e "${GREEN}    [+] File exported to: routermcs_results.csv${NC}"
fi

[[ "$DEBUG" == "true" ]] && set -x
