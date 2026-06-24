#!/usr/bin/env bash
# net-sleep-guard — prevents sleep while network is active
# Usage: ./net-sleep-guard.sh  (edit the config block below to change defaults)

# CONFIGURATION
# THRESHOLD_MBPS  — minimum speed to count as "active". e.g. 1 = 1 MB/s, 0.5 = 500 KB/s
THRESHOLD_MBPS=2
# QUIET_MINUTES   — how long traffic must stay below the threshold before sleep is allowed
QUIET_MINUTES=15
# UNIT            — display unit for speeds. "MB" = megabytes per second (MBps), "Mb" = megabits per second (Mbps)
UNIT="MB"

# ── derived values (do not edit below this line) ──────────────────────────────
QUIET_TIME=$(( QUIET_MINUTES * 60 ))
INTERVAL=1

# threshold is always stored internally as bytes/s
if [[ "$UNIT" == "Mb" ]]; then
    # 1 Mbps = 125000 bytes/s
    THRESHOLD_BPS=$(awk "BEGIN{printf \"%d\", $THRESHOLD_MBPS * 125000}")
else
    # 1 MB/s = 1000000 bytes/s
    THRESHOLD_BPS=$(awk "BEGIN{printf \"%d\", $THRESHOLD_MBPS * 1000000}")
fi

# ── write inner worker script via Python (avoids all heredoc escaping issues) ─
TMPSCRIPT=$(mktemp /tmp/net-sleep-guard-XXXXXX.sh)
chmod +x "$TMPSCRIPT"
trap 'rm -f "$TMPSCRIPT"' EXIT

python3 - "$TMPSCRIPT" "$THRESHOLD_MBPS" "$THRESHOLD_BPS" "$QUIET_TIME" "$INTERVAL" "$UNIT" << 'PYEOF'
import sys

out_path       = sys.argv[1]
threshold_disp = sys.argv[2]   # display value (MB/s or Mb/s)
threshold_bps  = sys.argv[3]   # internal bytes/s
quiet_time     = sys.argv[4]
interval       = sys.argv[5]
unit           = sys.argv[6]   # "MB" or "Mb"

# unit label strings
if unit == "Mb":
    unit_label   = "Mb/s"
    # fmt_rate converts bytes/s → Mb/s (×8 / 1,000,000)
    fmt_rate_fn = r"""
fmt_rate() {
    local bps=$1
    local bits=$(( bps * 8 ))
    if   (( bits >= 1000000000 )); then awk "BEGIN{printf \"%.2f Gb/s\", $bits/1e9}"
    elif (( bits >= 1000000    )); then awk "BEGIN{printf \"%.2f Mb/s\", $bits/1e6}"
    elif (( bits >= 1000       )); then awk "BEGIN{printf \"%.1f Kb/s\", $bits/1e3}"
    else echo "${bits} b/s"
    fi
}"""
else:
    unit_label   = "MB/s"
    fmt_rate_fn = r"""
fmt_rate() {
    local bps=$1
    if   (( bps >= 1000000000 )); then awk "BEGIN{printf \"%.2f GB/s\", $bps/1e9}"
    elif (( bps >= 1000000    )); then awk "BEGIN{printf \"%.2f MB/s\", $bps/1e6}"
    elif (( bps >= 1000       )); then awk "BEGIN{printf \"%.1f KB/s\", $bps/1e3}"
    else echo "${bps} B/s"
    fi
}"""

script = r"""#!/usr/bin/env bash

RESET=$(tput sgr0   2>/dev/null)
BOLD=$(tput bold    2>/dev/null)
DIM=$(tput dim      2>/dev/null)
GREEN=$(tput setaf 2  2>/dev/null)
YELLOW=$(tput setaf 3 2>/dev/null)
RED=$(tput setaf 1    2>/dev/null)
CYAN=$(tput setaf 6   2>/dev/null)
BLUE=$(tput setaf 4   2>/dev/null)
MAGENTA=$(tput setaf 5 2>/dev/null)
WHITE=$(tput setaf 7  2>/dev/null)
GREY=$(tput setaf 8   2>/dev/null)

THRESHOLD_DISP=""" + threshold_disp + r"""
THRESHOLD_BPS=""" + threshold_bps + r"""
QUIET_TIME=""" + quiet_time + r"""
INTERVAL=""" + interval + r"""
UNIT_LABEL=""" + '"' + unit_label + '"' + r"""
""" + fmt_rate_fn + r"""

net_bytes() {
    awk 'NR>2 && $1 !~ /^lo:/ {
        gsub(/:/, " ", $1); rx += $2; tx += $10
    } END { print rx+0, tx+0 }' /proc/net/dev
}

draw_bar() {
    local filled=$1 width=40 i bar="" emp=""
    (( filled > width )) && filled=$width
    local empty=$(( width - filled ))
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty;  i++ )); do emp+="░"; done
    printf '%s' "$bar$emp"
}

cleanup() {
    tput cnorm 2>/dev/null
    printf '\n  %s✔ Inhibitor released.%s\n' "$GREEN" "$RESET"
    exit 0
}
trap cleanup INT TERM

tput civis 2>/dev/null

read -r prev_rx prev_tx < <(net_bytes)
prev_time=$(date +%s)
low_start=0

while true; do
    sleep "$INTERVAL"

    read -r cur_rx cur_tx < <(net_bytes)
    cur_time=$(date +%s)
    dt=$(( cur_time - prev_time ))
    (( dt < 1 )) && dt=1

    rx_bps=$(( (cur_rx - prev_rx) / dt ))
    tx_bps=$(( (cur_tx - prev_tx) / dt ))
    total_bps=$(( rx_bps + tx_bps ))

    if (( total_bps >= THRESHOLD_BPS )); then
        low_start=0
        remaining=$QUIET_TIME
    else
        (( low_start == 0 )) && low_start=$cur_time
        elapsed=$(( cur_time - low_start ))
        remaining=$(( QUIET_TIME - elapsed ))
        (( remaining < 0 )) && remaining=0
    fi

    min=$(( remaining / 60 ))
    sec=$(( remaining % 60 ))
    progress=$(( (QUIET_TIME - remaining) * 100 / QUIET_TIME ))
    filled=$(( progress * 40 / 100 ))

    if (( low_start == 0 )); then
        s_icon="●"; s_label="Active — sleep blocked    "; s_col="$GREEN"
    elif (( remaining > QUIET_TIME / 2 )); then
        s_icon="◑"; s_label="Cooling down              "; s_col="$YELLOW"
    elif (( remaining > 0 )); then
        s_icon="◔"; s_label="Almost idle               "; s_col="$RED"
    else
        s_icon="○"; s_label="Releasing inhibitor...    "; s_col="$RED"
    fi

    if   (( total_bps >= THRESHOLD_BPS ));       then bar_col="$GREEN"
    elif (( remaining > QUIET_TIME * 6 / 10 ));  then bar_col="$YELLOW"
    else                                               bar_col="$RED"
    fi

    rx_str=$(fmt_rate "$rx_bps")
    tx_str=$(fmt_rate "$tx_bps")
    tot_str=$(fmt_rate "$total_bps")
    bar_str=$(draw_bar "$filled")

    clear
    printf '\n'
    printf '  %s┌──────────────────────────────────────────────────────┐%s\n' "$GREY" "$RESET"
    printf '  %s│%s  %s%s⏻  net-sleep-guard v0.1%s by Psystec%s%s\n' "$GREY" "$RESET" "$CYAN" "$BOLD" "$RESET" "$GREY" "$RESET"
    printf '  %s├──────────────────────────────────────────────────────┤%s\n' "$GREY" "$RESET"
    printf '  %s│%s  %s↓%s Download   %s%s%-14s%s  %s↑%s Upload  %s%s%-10s%s%s %s\n' "$GREY" "$RESET" "$CYAN" "$RESET" "$WHITE" "$BOLD" "$rx_str" "$RESET" "$MAGENTA" "$RESET" "$WHITE" "$BOLD" "$tx_str" "$RESET" "$GREY" "$RESET"
    printf '  %s│%s  %s⇅%s Total      %s%s%-14s%s  %s⚑%s Limit   %s%s%s %s%s%s %s\n' "$GREY" "$RESET" "$BLUE" "$RESET" "$WHITE" "$BOLD" "$tot_str" "$RESET" "$GREY" "$RESET" "$WHITE" "$BOLD" "$THRESHOLD_DISP" "$UNIT_LABEL" "$RESET" "$GREY" "$RESET"
    printf '  %s├──────────────────────────────────────────────────────┤%s\n' "$GREY" "$RESET"
    printf '  %s│%s  %s%s%s  %s%s%3d%%%s%s%s\n' "$GREY" "$RESET" "$bar_col" "$bar_str" "$RESET" "$WHITE" "$BOLD" "$progress" "$RESET" "$GREY" "$RESET"
    printf '  %s│%s  %sCooldown%s  %s%s%02d:%02d%s  until sleep unlocks %s%s\n' "$GREY" "$RESET" "$DIM" "$RESET" "$WHITE" "$BOLD" "$min" "$sec" "$RESET" "$GREY" "$RESET"
    printf '  %s├──────────────────────────────────────────────────────┤%s\n' "$GREY" "$RESET"
    printf '  %s│%s  %s%s%s%s %s%s%s%s%s%s\n' "$GREY" "$RESET" "$s_col" "$BOLD" "$s_icon" "$RESET" "$s_col" "$s_label" "$RESET" "$GREY" "$RESET"
    printf '  %s└──────────────────────────────────────────────────────┘%s\n' "$GREY" "$RESET"
    printf '\n  %sCtrl-C to release inhibitor manually%s\n' "$DIM" "$RESET"

    if (( low_start != 0 && remaining == 0 )); then
        tput cnorm 2>/dev/null
        printf '\n  %s%s✔ Traffic below threshold for %d min — sleep unlocked.%s\n' \
            "$GREEN" "$BOLD" "$(( QUIET_TIME / 60 ))" "$RESET"
        trap - EXIT
        exit 0
    fi

    prev_rx=$cur_rx
    prev_tx=$cur_tx
    prev_time=$cur_time
done
"""

with open(out_path, 'w') as f:
    f.write(script)
PYEOF

exec systemd-inhibit \
    --what=sleep \
    --who="net-sleep-guard" \
    --why="Network transfer in progress (threshold: ${THRESHOLD_MBPS} ${UNIT}ps)" \
    --mode=block \
    "$TMPSCRIPT"
