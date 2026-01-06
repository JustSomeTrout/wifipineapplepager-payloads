#!/bin/sh
# CGI API for Nautilus - Optimized with permanent cache

PAYLOAD_ROOT="/root/payloads/user"
PID_FILE="/tmp/nautilus_payload.pid"
OUTPUT_FILE="/tmp/nautilus_output.log"
CACHE_FILE="/tmp/nautilus_cache.json"

urldecode() {
    printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

list_payloads() {
    echo "Content-Type: application/json"
    echo ""
    # Serve cache if exists (built by payload.sh on startup)
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
    else
        echo '{"error":"Cache not ready. Refresh page."}'
    fi
}

run_payload() {
    rpath="$1"
    case "$rpath" in
        /root/payloads/*) ;;
        *) echo "Content-Type: text/plain"; echo ""; echo "Invalid path"; exit 1 ;;
    esac
    [ ! -f "$rpath" ] && { echo "Content-Type: text/plain"; echo ""; echo "Not found"; exit 1; }
    [ -f "$PID_FILE" ] && { kill $(cat "$PID_FILE") 2>/dev/null; rm -f "$PID_FILE"; }

    echo "Content-Type: text/event-stream"
    echo "Cache-Control: no-cache"
    echo ""

    # Create wrapper script that intercepts pager commands
    WRAPPER="/tmp/nautilus_wrapper_$$.sh"
    cat > "$WRAPPER" << 'WRAPPER_EOF'
#!/bin/bash
# Wrapper functions that echo to stdout AND call real commands

_nautilus_emit() {
    local color="$1"
    shift
    local text="$*"
    # Output for web console
    if [ -n "$color" ]; then
        echo "[${color}] ${text}"
    else
        echo "$text"
    fi
}

LOG() {
    local color=""
    if [ "$#" -gt 1 ]; then
        color="$1"
        shift
    fi
    _nautilus_emit "$color" "$@"
    /usr/bin/LOG ${color:+"$color"} "$@" 2>/dev/null || true
}

ALERT() {
    # Display in Nautilus only - don't pop up on pager
    echo "[PROMPT:alert] $*" >&2
    sleep 0.1
    _wait_response ""
}

ERROR_DIALOG() {
    # Display in Nautilus only - don't pop up on pager
    echo "[PROMPT:error] $*" >&2
    sleep 0.1
    _wait_response ""
}

LED() {
    _nautilus_emit "blue" "LED: $*"
    /usr/bin/LED "$@" 2>/dev/null || true
}

# Helper to wait for response
_wait_response() {
    local resp_file="/tmp/nautilus_response"
    local default="$1"
    rm -f "$resp_file"
    local timeout=300
    while [ ! -f "$resp_file" ] && [ $timeout -gt 0 ]; do
        sleep 0.5
        timeout=$((timeout - 1))
    done
    if [ -f "$resp_file" ]; then
        cat "$resp_file"
        rm -f "$resp_file"
    else
        echo -n "$default"
    fi
}

CONFIRMATION_DIALOG() {
    local msg="$*"
    # Write prompt to stderr (stdout is captured by $())
    echo "[PROMPT:confirm] $msg" >&2
    sleep 0.1
    local resp=$(_wait_response "0")
    if [ "$resp" = "1" ]; then
        echo -n "1"
    else
        echo -n "0"
    fi
}

PROMPT() {
    local msg="$*"
    echo "[PROMPT:text] $msg" >&2
    _wait_response ""
}

TEXT_PICKER() {
    local title="$1"
    local default="$2"
    echo "[PROMPT:text:$default] $title" >&2
    _wait_response "$default"
}

NUMBER_PICKER() {
    local title="$1"
    local default="$2"
    echo "[PROMPT:number:$default] $title" >&2
    _wait_response "$default"
}

IP_PICKER() {
    local title="$1"
    local default="$2"
    echo "[PROMPT:ip:$default] $title" >&2
    _wait_response "$default"
}

MAC_PICKER() {
    local title="$1"
    local default="$2"
    echo "[PROMPT:mac:$default] $title" >&2
    _wait_response "$default"
}

SPINNER() {
    _nautilus_emit "cyan" "SPINNER: $*"
    /usr/bin/SPINNER "$@" 2>/dev/null || true
}

SPINNER_STOP() {
    _nautilus_emit "cyan" "SPINNER_STOP"
    /usr/bin/SPINNER_STOP 2>/dev/null || true
}

export -f LOG ALERT ERROR_DIALOG LED CONFIRMATION_DIALOG PROMPT TEXT_PICKER NUMBER_PICKER IP_PICKER MAC_PICKER SPINNER SPINNER_STOP _nautilus_emit _wait_response

# Run the actual payload
cd "$(dirname "$1")"
source "$1"
WRAPPER_EOF
    chmod +x "$WRAPPER"

    : > "$OUTPUT_FILE"

    # Run wrapper in background, output to log file
    /bin/bash "$WRAPPER" "$rpath" >> "$OUTPUT_FILE" 2>&1 &
    WRAPPER_PID=$!
    echo $WRAPPER_PID > "$PID_FILE"

    sent_lines=0

    # Poll the output file
    while kill -0 $WRAPPER_PID 2>/dev/null || [ $(wc -l < "$OUTPUT_FILE") -gt $sent_lines ]; do
        current_lines=$(wc -l < "$OUTPUT_FILE")
        if [ $current_lines -gt $sent_lines ]; then
            tail -n +$((sent_lines + 1)) "$OUTPUT_FILE" | head -n $((current_lines - sent_lines)) | while IFS= read -r line; do
            escaped=$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')
            case "$line" in
                "[PROMPT:"*)
                    inner="${line#\[PROMPT:}"
                    type="${inner%%\]*}"
                    msg="${inner#*\] }"
                    if echo "$type" | grep -q ':'; then
                        default="${type#*:}"
                        type="${type%%:*}"
                    else
                        default=""
                    fi
                    escaped_msg=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
                    escaped_def=$(printf '%s' "$default" | sed 's/\\/\\\\/g; s/"/\\"/g')
                    printf 'event: prompt\ndata: {"type":"%s","message":"%s","default":"%s"}\n\n' "$type" "$escaped_msg" "$escaped_def"
                    continue ;;
            esac
            color=""
            case "$line" in
                "[red]"*) color="red" ;;
                "[green]"*) color="green" ;;
                "[yellow]"*) color="yellow" ;;
                "[cyan]"*) color="cyan" ;;
                "[blue]"*) color="blue" ;;
                "[magenta]"*) color="magenta" ;;
            esac
                if [ -n "$color" ]; then
                    printf 'data: {"text":"%s","color":"%s"}\n\n' "$escaped" "$color"
                else
                    printf 'data: {"text":"%s"}\n\n' "$escaped"
                fi
            done
            sent_lines=$current_lines
        fi
        sleep 0.2
    done
    printf 'event: done\ndata: {"status":"complete"}\n\n'
    rm -f "$WRAPPER" "$PID_FILE"
}

respond() {
    echo "Content-Type: application/json"
    echo ""
    local response="$1"
    echo "$response" > "/tmp/nautilus_response"
    echo '{"status":"ok"}'
}

stop_payload() {
    echo "Content-Type: application/json"
    echo ""
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE") 2>/dev/null
        rm -f "$PID_FILE"
        echo '{"status":"stopped"}'
    else
        echo '{"status":"not_running"}'
    fi
}

action=""
rpath=""
response=""
IFS='&'
for param in $QUERY_STRING; do
    key="${param%%=*}"
    val="${param#*=}"
    case "$key" in
        action) action="$val" ;;
        path) rpath=$(urldecode "$val") ;;
        response) response=$(urldecode "$val") ;;
    esac
done
unset IFS

case "$action" in
    list) list_payloads ;;
    run) run_payload "$rpath" ;;
    stop) stop_payload ;;
    respond) respond "$response" ;;
    refresh) /root/payloads/user/general/nautilus/build_cache.sh; echo "Content-Type: application/json"; echo ""; echo '{"status":"refreshed"}' ;;
    *) echo "Content-Type: application/json"; echo ""; echo '{"error":"Unknown action"}' ;;
esac

