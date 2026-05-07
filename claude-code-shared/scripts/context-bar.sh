#!/bin/bash

# Color theme: gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
# Preview colors with: bash scripts/color-preview.sh
COLOR="blue"

# Color codes
C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'  # explicit gray for default text
C_BAR_EMPTY='\033[38;5;238m'
case "$COLOR" in
    orange)   C_ACCENT='\033[38;5;173m' ;;
    blue)     C_ACCENT='\033[38;5;74m' ;;
    teal)     C_ACCENT='\033[38;5;66m' ;;
    green)    C_ACCENT='\033[38;5;71m' ;;
    lavender) C_ACCENT='\033[38;5;139m' ;;
    rose)     C_ACCENT='\033[38;5;132m' ;;
    gold)     C_ACCENT='\033[38;5;136m' ;;
    slate)    C_ACCENT='\033[38;5;60m' ;;
    cyan)     C_ACCENT='\033[38;5;37m' ;;
    *)        C_ACCENT="$C_GRAY" ;;  # gray: all same color
esac

input=$(cat)

# Extract model, directory, and cwd
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Get git branch, uncommitted file count, and sync status
branch=""
git_status=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        # Count uncommitted files
        file_count=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | wc -l | tr -d ' ')

        # Check sync status with upstream
        sync_status=""
        upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
        if [[ -n "$upstream" ]]; then
            # Get last fetch time
            fetch_head="$cwd/.git/FETCH_HEAD"
            fetch_ago=""
            if [[ -f "$fetch_head" ]]; then
                fetch_time=$(stat -f %m "$fetch_head" 2>/dev/null || stat -c %Y "$fetch_head" 2>/dev/null)
                if [[ -n "$fetch_time" ]]; then
                    now=$(date +%s)
                    diff=$((now - fetch_time))
                    if [[ $diff -lt 60 ]]; then
                        fetch_ago="<1m ago"
                    elif [[ $diff -lt 3600 ]]; then
                        fetch_ago="$((diff / 60))m ago"
                    elif [[ $diff -lt 86400 ]]; then
                        fetch_ago="$((diff / 3600))h ago"
                    else
                        fetch_ago="$((diff / 86400))d ago"
                    fi
                fi
            fi

            counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
            ahead=$(echo "$counts" | cut -f1)
            behind=$(echo "$counts" | cut -f2)
            if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
                if [[ -n "$fetch_ago" ]]; then
                    sync_status="synced ${fetch_ago}"
                else
                    sync_status="synced"
                fi
            elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
                sync_status="${ahead} ahead"
            elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
                sync_status="${behind} behind"
            else
                sync_status="${ahead} ahead, ${behind} behind"
            fi
        else
            sync_status="no upstream"
        fi

        # Build git status string
        if [[ "$file_count" -eq 0 ]]; then
            git_status="(0 files uncommitted, ${sync_status})"
        elif [[ "$file_count" -eq 1 ]]; then
            # Show the actual filename when only one file is uncommitted
            single_file=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | head -1 | sed 's/^...//')
            git_status="(${single_file} uncommitted, ${sync_status})"
        else
            git_status="(${file_count} files uncommitted, ${sync_status})"
        fi
    fi
fi

max_context=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
max_k=$((max_context / 1000))
if [[ $max_k -ge 1000 ]]; then
    max_display="$((max_k / 1000))M"
else
    max_display="${max_k}k"
fi

# Calculate context bar — prefer five_hour session usage over per-conversation context window
bar_width=10
session_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [[ -n "$session_pct" && "$session_pct" != "null" ]]; then
    pct=$(printf '%.0f' "$session_pct")
    pct_label="used"
else
    pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
    pct_label="of ${max_display} ctx"
fi
pct=$(( pct > 100 ? 100 : pct ))

bar=""
for ((i=0; i<bar_width; i++)); do
    bar_start=$((i * 10))
    progress=$((pct - bar_start))
    if [[ $progress -ge 8 ]]; then
        bar+="${C_ACCENT}█${C_RESET}"
    elif [[ $progress -ge 3 ]]; then
        bar+="${C_ACCENT}▄${C_RESET}"
    else
        bar+="${C_BAR_EMPTY}░${C_RESET}"
    fi
done

ctx="${bar} ${C_GRAY}${pct}% ${pct_label}"

# Calculate time until token refresh from rate_limits.five_hour.resets_at (Unix epoch seconds)
resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
token_refresh=""
if [[ -n "$resets_at" && "$resets_at" != "null" ]]; then
    now=$(date +%s)
    secs_until_reset=$((resets_at - now))
    if [[ $secs_until_reset -le 0 ]]; then
        token_refresh="  |  ${C_GRAY}🔄 now"
    else
        refresh_hrs=$((secs_until_reset / 3600))
        refresh_min=$(( (secs_until_reset % 3600) / 60 ))
        if [[ $refresh_hrs -gt 0 ]]; then
            token_refresh="  |  ${C_GRAY}🔄 ${refresh_hrs}h ${refresh_min}m"
        else
            token_refresh="  |  ${C_GRAY}🔄 ${refresh_min}m"
        fi
    fi
fi

# Get caveman mode badge
caveman_badge=""
CAVEMAN_FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"
if [ ! -L "$CAVEMAN_FLAG" ] && [ -f "$CAVEMAN_FLAG" ]; then
    CAVEMAN_MODE=$(head -c 64 "$CAVEMAN_FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
    CAVEMAN_MODE=$(printf '%s' "$CAVEMAN_MODE" | tr -cd 'a-z0-9-')
    case "$CAVEMAN_MODE" in
      off|lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress)
        if [ "$CAVEMAN_MODE" = "full" ]; then
            caveman_badge="  |  \033[38;5;172m[CAVEMAN]\033[0m"
        else
            SUFFIX=$(printf '%s' "$CAVEMAN_MODE" | tr '[:lower:]' '[:upper:]')
            caveman_badge="  |  \033[38;5;172m[CAVEMAN:${SUFFIX}]\033[0m"
        fi
        ;;
    esac
else
    caveman_badge="  |  \033[38;5;196m[CAVEMAN:DISABLED]\033[0m"
fi

# Line 1: Model | Dir | Branch
line1="${C_ACCENT}${model}${C_GRAY}  |  📁 ${dir}"
[[ -n "$branch" ]] && line1+="  | 🔀 ${branch} ${git_status}."

# Line 2: Context bar | Token refresh countdown | Caveman badge
line2="${ctx}${token_refresh}${caveman_badge}${C_RESET}"

printf '%b\n%b\n' "$line1" "$line2"
