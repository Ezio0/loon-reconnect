#!/bin/sh

result=0

log_event() {
    /usr/bin/printf '%s %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S %z')" "$1"
}

log_error() {
    log_event "$1" >&2
    result=1
    return 1
}

resolve_vpn_service() {
    if handler_id=$(/usr/bin/osascript -l JavaScript <<'LOON_RESOLVE_JXA'
function run() {
    ObjC.import('AppKit');
    var appURL = $.NSWorkspace.sharedWorkspace.URLForApplicationToOpenURL($.NSURL.URLWithString('loon://'));
    var identifier = ObjC.unwrap($.NSBundle.bundleWithURL(appURL).bundleIdentifier);
    if (!identifier) {
        throw new Error('No application is registered for loon://');
    }
    return identifier;
}
LOON_RESOLVE_JXA
    ); then
        case "$handler_id" in
            ''|*[!a-zA-Z0-9._-]*) log_error 'failed to identify the loon:// handler'; return 1 ;;
        esac
    else
        log_error 'failed to identify the loon:// handler'
        return 1
    fi
    if ! vpn_services=$(LC_ALL=C /usr/sbin/scutil --nc list 2>/dev/null); then
        log_error 'failed to list system VPN services'
        return 1
    fi
    # Match the enabled provider and its UUID, never a user-editable display name.
    if ! vpn_service=$(printf '%s\n' "$vpn_services" | /usr/bin/awk -v provider="[VPN:$handler_id]" '
        $1 == "*" && $4 == "VPN" && $NF == provider { count++; candidate = $3 }
        END {
            parts = split(candidate, uuid, "-")
            if (count == 1 && parts == 5 && candidate !~ /[^[:xdigit:]-]/ &&
                length(uuid[1]) == 8 && length(uuid[2]) == 4 && length(uuid[3]) == 4 &&
                length(uuid[4]) == 4 && length(uuid[5]) == 12) print candidate
            else exit 1
        }
    '); then
        log_error 'failed to find one enabled VPN service for the loon:// handler; no reconnect requested'
        return 1
    fi
}

read_vpn_state() {
    if vpn_status_output=$(LC_ALL=C /usr/sbin/scutil --nc status "$vpn_service" 2>/dev/null); then
        vpn_state=$(printf '%s\n' "$vpn_status_output" | /usr/bin/awk 'NR == 1 { print; exit }')
        case "$vpn_state" in
            Connected|Disconnected|Connecting|Disconnecting) return 0 ;;
            *) log_error 'failed to read a recognized VPN state'; return 1 ;;
        esac
    else
        code=$?
        log_error "failed to read VPN state (scutil exit $code)"
        return 1
    fi
}

wait_for_connection() {
    for poll in 1 2 3 4 5 6; do
        /bin/sleep 5
        read_vpn_state || return 2
        [ "$vpn_state" = Connected ] && return 0
    done
    return 1
}

ensure_connected() {
    read_vpn_state || return 1
    if [ "$vpn_state" = Connected ]; then
        log_event 'vpn Connected (system status)'
        return 0
    fi
    case "$vpn_state" in
        Connecting|Disconnecting)
            log_event "waiting for VPN transition ($vpn_state)"
            if wait_for_connection; then
                log_event 'vpn Connected (system status)'
                return 0
            else
                [ "$?" -eq 2 ] && return 1
            fi
            ;;
    esac
    for recovery_attempt in 1 2; do
        if [ "$vpn_state" != Disconnected ]; then
            log_error "failed to confirm VPN connection: still $vpn_state; no additional start requested"
            return 1
        fi
        if /usr/sbin/scutil --nc start "$vpn_service" >/dev/null 2>&1; then
            log_event "requested system VPN start (attempt $recovery_attempt/2)"
        else
            code=$?
            log_error "failed system VPN start (attempt $recovery_attempt/2, exit $code)"
        fi
        if wait_for_connection; then
            log_event 'vpn Connected (system status)'
            return 0
        else
            [ "$?" -eq 2 ] && return 1
        fi
    done
    log_error 'failed to confirm VPN connection after recovery'
}

send_action() {
    attempt_note=${2:+ (attempt $2)}
    # Allow activation so a suspended iPad app can handle the URL on macOS.
    if /usr/bin/open "$1"; then
        /usr/bin/printf '%s sent %s%s\n' \
            "$(/bin/date '+%Y-%m-%d %H:%M:%S %z')" "$1" "$attempt_note"
    else
        code=$?
        /usr/bin/printf '%s failed %s%s (open exit %s)\n' \
            "$(/bin/date '+%Y-%m-%d %H:%M:%S %z')" "$1" "$attempt_note" "$code" >&2
        result=1
    fi
}

hide_loon() {
    if hide_output=$(/usr/bin/osascript -l JavaScript <<'LOON_HIDE_JXA'
function run() {
    ObjC.import('AppKit');
    var appURL = $.NSWorkspace.sharedWorkspace.URLForApplicationToOpenURL($.NSURL.URLWithString('loon://'));
    var identifier = ObjC.unwrap($.NSBundle.bundleWithURL(appURL).bundleIdentifier);
    if (!identifier) {
        throw new Error('No application is registered for loon://');
    }
    var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(identifier);
    if (apps.count === 0) {
        return 'no running loon:// handler; nothing to hide';
    }
    for (var index = 0; index < apps.count; index++) {
        var app = apps.objectAtIndex(index);
        if (!app.isTerminated && !app.isHidden) {
            // Confirm the refreshed state below instead of the immediate return value.
            void app.hide;
        }
    }
    var deadline = Date.now() + 2000;
    while (Date.now() < deadline) {
        var allHidden = true;
        for (var index = 0; index < apps.count; index++) {
            var app = apps.objectAtIndex(index);
            if (!app.isTerminated && !app.isHidden) {
                allHidden = false;
            }
        }
        if (allHidden) {
            return 'hidden loon:// handler';
        }
        // AppKit refreshes visibility properties when the main run loop advances.
        $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));
    }
    throw new Error('The loon:// handler did not become hidden within 2 seconds');
}
LOON_HIDE_JXA
    ); then
        /usr/bin/printf '%s %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S %z')" "$hide_output"
    else
        code=$?
        /usr/bin/printf '%s failed to hide loon:// handler (osascript exit %s)\n' \
            "$(/bin/date '+%Y-%m-%d %H:%M:%S %z')" "$code" >&2
        result=1
    fi
}

# Begin scheduled cycle. Validate the recovery target before turning anything off.
resolve_vpn_service || exit 1
read_vpn_state || exit 1

# 即使关闭调用失败，也继续尝试开启。
send_action 'loon://off'
/bin/sleep 3
# 调用成功不代表 VPN 已恢复；固定补发一次 on，不重复 off。
for attempt in 1 2; do
    send_action 'loon://on' "$attempt/2"
    /bin/sleep 10
done
send_action 'loon://update?sub=all'
/bin/sleep 2
ensure_connected || result=1
hide_loon

exit "$result"
