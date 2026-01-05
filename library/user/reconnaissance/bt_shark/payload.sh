#!/bin/bash
# Title: BT Shark
# Description: Passive BLE RSSI tracker with MAC rotation handling, pruning, and geiger-style feedback
# Made for Pager Version: 1.0.4
# Author: Trout
# The Shark: apex predator of the fish army.
# Equipped with RSSI electroreception, the shark hunts Bluetooth prey.
# No MAC rotation can hide you. The shark smells blood.

# ===============================
# CONFIGURATION
# ===============================
SCAN_DURATION=30
LOOT_DIR="/root/loot/bluetooth"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEVICES_FILE="$LOOT_DIR/devices_$TIMESTAMP.txt"
DEBUG_LOG="$LOOT_DIR/debug_$TIMESTAMP.log"
BTMON_RAW="/tmp/btmon_raw_capture"

mkdir -p "$LOOT_DIR"

# ===============================
# GLOBALS
# ===============================
SCAN_PID=""
BTMON_PID=""
LAST_POS=0
NO_SIGNAL=0
LAST_SEEN_MAC=""

# ===============================
# FUNCTIONS
# ===============================
DBG() {
    echo "[DBG] $1" >> "$DEBUG_LOG"
    LOG "yellow" "[DBG] $1"
}

cleanup() {
    DBG "Cleaning up"
    [ -n "$SCAN_PID" ] && kill "$SCAN_PID" 2>/dev/null
    [ -n "$BTMON_PID" ] && kill "$BTMON_PID" 2>/dev/null
    killall btmon hcitool 2>/dev/null
    sleep 0.5
    bluetoothctl scan off 2>/dev/null
    rm -f "$BTMON_RAW" "$SCAN_OUT" "$SCAN_OUT.clean"
    LOG "cyan" "Done. Debug log: $DEBUG_LOG"
    exit 0
}
trap cleanup EXIT INT TERM

# NOTE: LOG, RINGTONE, VIBRATE, NUMBER_PICKER are provided by Pager environment

get_signal_bar() {
    local rssi=$1
    if   [ "$rssi" -gt -55 ]; then echo "██████████"
    elif [ "$rssi" -gt -60 ]; then echo "█████████░"
    elif [ "$rssi" -gt -65 ]; then echo "████████░░"
    elif [ "$rssi" -gt -70 ]; then echo "███████░░░"
    elif [ "$rssi" -gt -75 ]; then echo "██████░░░░"
    elif [ "$rssi" -gt -80 ]; then echo "█████░░░░░"
    elif [ "$rssi" -gt -85 ]; then echo "████░░░░░░"
    elif [ "$rssi" -gt -90 ]; then echo "███░░░░░░░"
    elif [ "$rssi" -gt -95 ]; then echo "██░░░░░░░░"
    elif [ "$rssi" -gt -100 ]; then echo "█░░░░░░░░░"
    else                           echo "░░░░░░░░░░"
    fi
}

# OUI database path
OUI_DB="/root/payloads/user/reconnaissance/bt_shark/known_oui.txt"

# Get manufacturer from MAC address
get_manufacturer() {
    local mac="$1"
    # Extract OUI (first 6 chars, no colons)
    local oui=$(echo "$mac" | tr -d ':' | cut -c1-6 | tr 'a-f' 'A-F')
    if [ -f "$OUI_DB" ]; then
        grep -i "^$oui|" "$OUI_DB" 2>/dev/null | cut -d'|' -f2 | head -1
    fi
}

# Get OUI from MAC
get_oui() {
    echo "$1" | tr -d ':' | cut -c1-6 | tr 'a-f' 'A-F'
}

# Check if MAC is randomized (locally administered)
# Second hex char is 2,3,6,7,A,B,E,F when LA bit is set
is_random_mac() {
    local second_char=$(echo "$1" | cut -c2 | tr 'a-f' 'A-F')
    case "$second_char" in
        2|3|6|7|A|B|E|F) return 0 ;;  # true - is random
        *) return 1 ;;  # false - not random
    esac
}

# ===============================
# DEBUG CHECKS
# ===============================
LOG "cyan" "BT Shark v4"
DBG "Debug log: $DEBUG_LOG"

DBG "Checking commands..."
command -v bluetoothctl >/dev/null || { LOG "red" "bluetoothctl missing"; exit 1; }
command -v btmon >/dev/null || { LOG "red" "btmon missing"; exit 1; }
command -v hcitool >/dev/null || { LOG "red" "hcitool missing"; exit 1; }
DBG "Commands OK"

DBG "Resetting BT adapter..."
killall btmon hcitool 2>/dev/null
bluetoothctl scan off 2>/dev/null
hciconfig hci0 down 2>/dev/null
sleep 1
hciconfig hci0 up 2>/dev/null
sleep 1
bluetoothctl power on >/dev/null 2>&1
sleep 1
DBG "BT adapter ready"

# ===============================
# PHASE 1 – BLE SCAN WITH RSSI
# ===============================
LOG "Scanning ($SCAN_DURATION sec)..."
DBG "Starting btmon scan phase"

# Start btmon capture
btmon > "$BTMON_RAW" 2>&1 &
BTMON_PID=$!

# Start BLE scan
hcitool lescan --duplicates >/dev/null 2>&1 &
SCAN_PID=$!

sleep "$SCAN_DURATION"

kill $SCAN_PID 2>/dev/null
kill $BTMON_PID 2>/dev/null
sleep 0.5

DBG "Scan complete, parsing btmon output..."

# Parse btmon output: extract MAC addresses with their best RSSI
# Format: MAC|RSSI|Name
PARSED_FILE="/tmp/bt_parsed_$$"
> "$PARSED_FILE"

# Extract Address, RSSI, and Company ID from btmon output
# Company ID stays constant even when MAC rotates - use for fingerprinting
awk '
/Address:/ && !/type/ {
    if (match($0, /[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]/)) {
        mac = substr($0, RSTART, 17)
        company = ""
    }
}
/Company:/ && mac != "" {
    # Extract company name (e.g., "Samsung Electronics Co. Ltd.")
    if (match($0, /Company: [^(]+/)) {
        company = substr($0, RSTART+9, RLENGTH-9)
        gsub(/^ +| +$/, "", company)  # trim whitespace
    }
}
/RSSI:/ && mac != "" {
    if (match($0, /-[0-9]+/)) {
        rssi = substr($0, RSTART, RLENGTH)
        if (company == "") company = "Unknown"
        print mac "|" rssi "|" company
        mac = ""
        company = ""
    }
}
' "$BTMON_RAW" > "/tmp/bt_raw_macs_$$"

DBG "Raw MACs found: $(wc -l < /tmp/bt_raw_macs_$$)"

# Get unique MACs with best RSSI, keep company info
# Format: MAC|RSSI|Company
sort -t'|' -k1,1 -k2,2rn "/tmp/bt_raw_macs_$$" | \
    awk -F'|' '!seen[$1]++ {print $1 "|" $2 "|" $3}' > "/tmp/bt_unique_$$"

# Add [Random] flag for random MACs, use Company from btmon if available
while IFS='|' read -r MAC RSSI COMPANY; do
    if is_random_mac "$MAC"; then
        # For random MACs, show company from advertising data if available
        if [ -n "$COMPANY" ] && [ "$COMPANY" != "Unknown" ]; then
            MFG="[R] $COMPANY"
        else
            MFG="[Random]"
        fi
    else
        # For real MACs, prefer OUI lookup, fallback to btmon company
        MFG=$(get_manufacturer "$MAC")
        if [ -z "$MFG" ]; then
            if [ -n "$COMPANY" ] && [ "$COMPANY" != "Unknown" ]; then
                MFG="$COMPANY"
            else
                MFG="Unknown"
            fi
        fi
    fi
    # Output with RSSI first for sorting, then rearrange
    echo "$RSSI|$MAC|$MFG|$COMPANY"
done < "/tmp/bt_unique_$$" | sort -rn | awk -F'|' '{print $2"|"$1"|"$3"|"$4}' > "$DEVICES_FILE"

rm -f "/tmp/bt_raw_macs_$$" "/tmp/bt_unique_$$" "$PARSED_FILE"

DEVICE_COUNT=$(wc -l < "$DEVICES_FILE")
[ "$DEVICE_COUNT" -eq 0 ] && { LOG "red" "No BLE devices found"; exit 1; }

LOG "green" "Found $DEVICE_COUNT devices"
LOG ""

# ===============================
# PHASE 2 – SELECT TARGET
# ===============================
LOG "cyan" "Device List:"
IDX=1
while IFS='|' read -r MAC RSSI MFG; do
    BAR=$(get_signal_bar "$RSSI")
    LOG "[$IDX] $MFG"
    LOG "    $BAR ${RSSI}dBm"
    LOG "    $MAC"
    IDX=$((IDX + 1))
done < "$DEVICES_FILE"

LOG ""
LOG "yellow" "Select device..."
sleep 5

SELECTION=$(NUMBER_PICKER "Device (1-$DEVICE_COUNT)" 1)
PICKER_EXIT=$?
DBG "NUMBER_PICKER returned: $SELECTION (exit: $PICKER_EXIT)"
[ $PICKER_EXIT -ne 0 ] && exit 0

TARGET_LINE=$(sed -n "${SELECTION}p" "$DEVICES_FILE")
TARGET_MAC=$(echo "$TARGET_LINE" | cut -d'|' -f1)
TARGET_RSSI=$(echo "$TARGET_LINE" | cut -d'|' -f2)
TARGET_MFG=$(echo "$TARGET_LINE" | cut -d'|' -f3)
TARGET_COMPANY=$(echo "$TARGET_LINE" | cut -d'|' -f4)

DBG "Selected: $TARGET_MFG ($TARGET_MAC) @ ${TARGET_RSSI}dBm, Company: $TARGET_COMPANY"

LOG ""
LOG "green" "Tracking: $TARGET_MFG"
LOG ""

# ===============================
# PHASE 3 – BLE RSSI TRACKING
# ===============================

# Reset adapter to clean state before tracking
DBG "Resetting BT adapter for tracking..."
killall btmon hcitool 2>/dev/null
bluetoothctl scan off 2>/dev/null
hciconfig hci0 down 2>/dev/null
sleep 1
hciconfig hci0 up 2>/dev/null
sleep 1
bluetoothctl power on >/dev/null 2>&1
sleep 1

LOG "yellow" "Press B to stop"

# Get OUI for smart tracking, check if random MAC
TARGET_OUI=$(get_oui "$TARGET_MAC")
IS_RANDOM_TARGET=0
if is_random_mac "$TARGET_MAC"; then
    IS_RANDOM_TARGET=1
    DBG "Target is RANDOM MAC - will use RSSI-only tracking"
    LOG "yellow" "Random MAC - RSSI tracking"
else
    DBG "Target has real OUI - will use OUI+RSSI tracking"
fi
DBG "Tracking: $TARGET_MAC (OUI: $TARGET_OUI, Mfg: $TARGET_MFG, Random: $IS_RANDOM_TARGET)"
LOG "cyan" "Target: $TARGET_MFG"

TRACK_MAC="$TARGET_MAC"
LAST_RSSI="$TARGET_RSSI"
NO_SIGNAL_COUNT=0
LOOP_COUNT=0

while true; do
    LOOP_COUNT=$((LOOP_COUNT + 1))

    # Burst scan: 3 seconds
    hcitool lescan --duplicates >/dev/null 2>&1 &
    SCAN_PID=$!
    timeout 3 btmon > "$BTMON_RAW" 2>&1
    kill $SCAN_PID 2>/dev/null

    SIZE=$(wc -c < "$BTMON_RAW" 2>/dev/null || echo 0)
    MAC_COUNT=$(grep -c "Address:" "$BTMON_RAW" 2>/dev/null || echo 0)
    [ $((LOOP_COUNT % 5)) -eq 0 ] && DBG "Burst $LOOP_COUNT, size=$SIZE, macs=$MAC_COUNT"

    if [ "$SIZE" -gt 100 ]; then
        # Try to find current MAC
        RSSI=""
        BLOCK=$(grep -i -A5 "Address: $TRACK_MAC" "$BTMON_RAW" | tail -10)
        [ $((LOOP_COUNT % 5)) -eq 0 ] && DBG "Looking for $TRACK_MAC, found=$(echo "$BLOCK" | wc -l) lines"
        if [ -n "$BLOCK" ]; then
            RSSI=$(echo "$BLOCK" | grep -oE 'RSSI: -[0-9]+' | tail -1 | grep -oE '\-[0-9]+')
        fi

        # If no signal, try smart MAC rotation detection
        if [ -z "$RSSI" ] && [ "$NO_SIGNAL_COUNT" -ge 3 ]; then
            if [ "$IS_RANDOM_TARGET" = "1" ] && [ -n "$TARGET_COMPANY" ] && [ "$TARGET_COMPANY" != "Unknown" ]; then
                DBG "Lost random MAC, searching by Company ID ($TARGET_COMPANY)..."
                # For random MACs with known company: find MACs advertising same company
                CANDIDATES=$(grep -B10 "Company: $TARGET_COMPANY" "$BTMON_RAW" | \
                             grep -oE "Address: [0-9A-Fa-f:]{17}" | cut -d' ' -f2 | sort -u)
            elif [ "$IS_RANDOM_TARGET" = "1" ]; then
                DBG "Lost random MAC (no company), searching by RSSI proximity..."
                # For random MACs without company: find any random MAC
                CANDIDATES=$(grep -oE "Address: [0-9A-Fa-f:]{17}" "$BTMON_RAW" | \
                             cut -d' ' -f2 | sort -u)
            else
                DBG "Lost signal, searching same OUI ($TARGET_OUI)..."
                # For real MACs: find MACs with same OUI
                CANDIDATES=$(grep -oE "Address: [0-9A-Fa-f:]{17}" "$BTMON_RAW" | \
                             grep -i "$(echo $TARGET_OUI | sed 's/../&:/g' | sed 's/:$//')" | \
                             cut -d' ' -f2 | sort -u)
            fi

            BEST_MAC=""
            BEST_RSSI=-999
            BEST_DIFF=999
            for CAND in $CANDIDATES; do
                [ "$CAND" = "$TRACK_MAC" ] && continue

                # For random target without company match, only consider other random MACs
                if [ "$IS_RANDOM_TARGET" = "1" ] && [ -z "$TARGET_COMPANY" -o "$TARGET_COMPANY" = "Unknown" ]; then
                    is_random_mac "$CAND" || continue
                fi

                CAND_BLOCK=$(grep -i -A10 "Address: $CAND" "$BTMON_RAW" | head -15)
                CAND_RSSI=$(echo "$CAND_BLOCK" | grep -oE 'RSSI: -[0-9]+' | tail -1 | grep -oE '\-[0-9]+')
                if [ -n "$CAND_RSSI" ]; then
                    # Find closest to last known RSSI
                    DIFF=$((CAND_RSSI - LAST_RSSI))
                    [ "$DIFF" -lt 0 ] && DIFF=$((-DIFF))
                    # With company match use looser threshold (20 dBm), without use tighter (10)
                    THRESHOLD=10
                    [ -n "$TARGET_COMPANY" ] && [ "$TARGET_COMPANY" != "Unknown" ] && THRESHOLD=20
                    [ "$IS_RANDOM_TARGET" != "1" ] && THRESHOLD=15
                    if [ "$DIFF" -lt "$THRESHOLD" ] && [ "$DIFF" -lt "$BEST_DIFF" ]; then
                        BEST_MAC="$CAND"
                        BEST_RSSI="$CAND_RSSI"
                        BEST_DIFF="$DIFF"
                    fi
                fi
            done

            if [ -n "$BEST_MAC" ]; then
                LOG "yellow" "MAC rotated!"
                DBG "Switched: $TRACK_MAC -> $BEST_MAC (RSSI: $BEST_RSSI, diff: $BEST_DIFF)"
                TRACK_MAC="$BEST_MAC"
                RSSI="$BEST_RSSI"
            fi
        fi

        if [ -n "$RSSI" ]; then
            NO_SIGNAL_COUNT=0
            LAST_RSSI="$RSSI"
            BAR=$(get_signal_bar "$RSSI")
            LOG "green" "$BAR ${RSSI}dBm"

            if [ "$RSSI" -gt -45 ]; then
                RINGTONE "H:d=16,o=6,b=200:c"
                VIBRATE 20
            elif [ "$RSSI" -gt -60 ]; then
                RINGTONE "S:d=16,o=5,b=200:c"
            else
                RINGTONE "W:d=16,o=4,b=200:c"
            fi
        else
            NO_SIGNAL_COUNT=$((NO_SIGNAL_COUNT + 1))
            if [ $((NO_SIGNAL_COUNT % 3)) -eq 0 ]; then
                LOG "yellow" "[........] Searching..."
            fi
        fi
    else
        NO_SIGNAL_COUNT=$((NO_SIGNAL_COUNT + 1))
        if [ $((NO_SIGNAL_COUNT % 3)) -eq 0 ]; then
            LOG "yellow" "[........] No data"
        fi
    fi
done
