#!/bin/bash
# Uses macOS system tools only. Compatible with the bundled Bash 3.2.
set -euo pipefail

# This identifier is retained for compatibility; it is not a macOS username.
label='com.ezio.loon-reconnect'
source_dir=$(cd "$(dirname "$BASH_SOURCE")" && pwd)
stage=''

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

configure_paths() {
    user_home=$1
    [[ "$user_home" == /* && -d "$user_home" ]] || fail 'An existing absolute home directory is required.'
    app_dir="$user_home/Library/Application Support/LoonAutomation"
    log_dir="$user_home/Library/Logs/LoonAutomation"
    agents_dir="$user_home/Library/LaunchAgents"
    plist="$agents_dir/$label.plist"
    backup_root="$user_home/Library/Application Support/LoonAutomationBackups"
    domain="gui/$(id -u)"
    service="$domain/$label"
}

usage() {
    cat <<'USAGE'
Loon Reconnect — macOS user LaunchAgent

Usage: bash scripts/loon-reconnect.sh COMMAND

  install [--hours N]  Install and load; defaults to 6 hours (1–8760).
  status              Show the scheduled task, not VPN connectivity.
  run                 Request one cycle now. This switches the VPN off/on.
  pause               Disable across logins and unload an idle task.
  resume              Enable and load, without immediately reconnecting.
  uninstall           Disable, unload, and move files/logs into a backup.
  help                Show this help.

Install from a logged-in user's Terminal, without sudo.
To change the interval or upgrade, uninstall (keeping the backup), then install.
USAGE
}

require_session() {
    [[ "$(uname -s)" == Darwin ]] || fail 'This tool requires macOS.'
    [[ "$(id -u)" != 0 ]] || fail 'Run as your normal user, without sudo.'
    launchctl print "$domain" >/dev/null 2>&1 ||
        fail 'No GUI login session is available. Log in to macOS first.'
}

reject_symlinks() {
    local path
    for path in "$app_dir" "$log_dir" "$plist" "$backup_root"; do
        [[ ! -L "$path" ]] || fail "Refusing to manage a symbolic link: $path"
    done
}

is_loaded() {
    launchctl print "$service" >/dev/null 2>&1
}

require_idle() {
    local info
    if info=$(launchctl print "$service" 2>/dev/null); then
        if printf '%s\n' "$info" | awk '
            /^\tstate = running/ { active = 1 }
            /^\tpid = [1-9]/ { active = 1 }
            /^\tactive count = / { if ($4 + 0 > 0) active = 1 }
            END { exit !active }
        '; then
            fail 'A reconnect cycle is active. Wait for it to finish and retry.'
        fi
    fi
}

validate_installation() {
    reject_symlinks
    [[ -f "$plist" && -f "$app_dir/reconnect.sh" ]] ||
        fail 'No complete installation was found.'
    /usr/bin/plutil -lint "$plist" >/dev/null || fail 'The installed plist is invalid.'
    [[ "$(/usr/bin/plutil -extract Label raw -o - "$plist")" == "$label" ]] ||
        fail 'The existing plist belongs to another task.'
    [[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$plist")" == /bin/sh ]] ||
        fail 'The existing task uses an unexpected interpreter.'
    [[ "$(/usr/bin/plutil -extract ProgramArguments.1 raw -o - "$plist")" == "$app_dir/reconnect.sh" ]] ||
        fail 'The existing task points to another script.'
}

cleanup_stage() {
    if [[ -n "$stage" && -d "$stage" ]]; then
        /bin/rm -f "$stage/reconnect.sh" "$stage/loon-reconnect.sh" "$stage/agent.plist"
        /bin/rmdir "$stage" 2>/dev/null || true
    fi
}

render_plist() {
    local target=$1 seconds=$2
    /usr/bin/plutil -create xml1 "$target"
    /usr/bin/plutil -insert Label -string "$label" "$target"
    /usr/bin/plutil -insert ProgramArguments -array "$target"
    /usr/bin/plutil -insert ProgramArguments.0 -string /bin/sh "$target"
    /usr/bin/plutil -insert ProgramArguments.1 -string "$app_dir/reconnect.sh" "$target"
    /usr/bin/plutil -insert StartInterval -integer "$seconds" "$target"
    /usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$target"
    /usr/bin/plutil -insert StandardOutPath -string "$log_dir/reconnect.log" "$target"
    /usr/bin/plutil -insert StandardErrorPath -string "$log_dir/reconnect.err.log" "$target"
    /usr/bin/plutil -insert Umask -integer 63 "$target"
    /usr/bin/plutil -lint "$target" >/dev/null
}

load_task() {
    /bin/sh -n "$app_dir/reconnect.sh" || fail 'The installed script has a syntax error.'
    launchctl enable "$service"
    if ! is_loaded; then
        if ! launchctl bootstrap "$domain" "$plist"; then
            launchctl disable "$service" ||
                fail 'Loading failed and disabling also failed. Files were kept; inspect the task before retrying.'
            fail 'Loading failed. Files were kept and the task was disabled; use resume to retry.'
        fi
    fi
}

install_command() {
    local hours=$1
    reject_symlinks
    [[ -f "$source_dir/reconnect.sh" ]] || fail 'Keep reconnect.sh beside this management script.'
    /bin/sh -n "$source_dir/reconnect.sh"
    /bin/bash -n "$source_dir/loon-reconnect.sh"
    umask 077
    /bin/mkdir -p "$user_home/Library/Application Support"
    stage=$(/usr/bin/mktemp -d "$user_home/Library/Application Support/.loon-install.XXXXXX")
    trap cleanup_stage EXIT
    /usr/bin/install -m 700 "$source_dir/reconnect.sh" "$stage/reconnect.sh"
    /usr/bin/install -m 700 "$source_dir/loon-reconnect.sh" "$stage/loon-reconnect.sh"
    render_plist "$stage/agent.plist" "$((hours * 3600))"

    if [[ -e "$app_dir" || -e "$plist" || -e "$log_dir" ]]; then
        if [[ -d "$app_dir" && -d "$log_dir" && -f "$plist" ]] &&
           /usr/bin/cmp -s "$stage/reconnect.sh" "$app_dir/reconnect.sh" &&
           /usr/bin/cmp -s "$stage/loon-reconnect.sh" "$app_dir/loon-reconnect.sh" &&
           /usr/bin/cmp -s "$stage/agent.plist" "$plist"; then
            load_task
            printf 'Already installed. Task is loaded; no reconnect was requested.\n'
            return
        fi
        fail 'Existing files differ. Nothing was replaced. Use uninstall to keep a backup before installing again.'
    fi
    is_loaded && fail 'A task with this identifier is already loaded. No files were replaced.'
    /bin/mkdir -p "$agents_dir"
    /usr/bin/install -d -m 700 "$app_dir" "$log_dir"
    /usr/bin/install -m 700 "$stage/reconnect.sh" "$app_dir/reconnect.sh"
    /usr/bin/install -m 700 "$stage/loon-reconnect.sh" "$app_dir/loon-reconnect.sh"
    /usr/bin/install -m 600 "$stage/agent.plist" "$plist"
    load_task
    printf 'Installed and loaded: every %s hours. No reconnect was requested.\n' "$hours"
    printf 'Logs: %s\n' "$log_dir"
}

status_command() {
    local info
    if info=$(launchctl print "$service" 2>/dev/null); then
        printf '%s\n' "$info" | awk '/^\t(state|runs|last exit code|run interval) =/ { print }'
    else
        printf 'Task is not loaded.\n'
    fi
    printf 'Configuration: %s\nLogs: %s\n' "$plist" "$log_dir"
}

pause_command() {
    require_idle
    launchctl disable "$service"
    # Check again before unloading; never use a forced kickstart or kill.
    require_idle
    if is_loaded; then
        launchctl bootout "$service"
    fi
    printf 'Task is paused across logins.\n'
}

uninstall_command() {
    local backup
    reject_symlinks
    if [[ ! -e "$plist" && ! -e "$app_dir" && ! -e "$log_dir" ]] && ! is_loaded; then
        printf 'Nothing is installed.\n'
        return
    fi
    validate_installation
    require_idle
    pause_command
    umask 077
    /bin/mkdir -p "$backup_root"
    backup=$(/usr/bin/mktemp -d "$backup_root/$(/bin/date '+%Y%m%d-%H%M%S').XXXXXX")
    /bin/mv "$plist" "$backup/$label.plist"
    /bin/mv "$app_dir" "$backup/scripts"
    if [[ -e "$log_dir" ]]; then
        /bin/mv "$log_dir" "$backup/logs"
    fi
    printf 'Uninstalled. Backup: %s\n' "$backup"
}

main() {
    local action hours=6
    if [[ $# -eq 0 ]]; then usage; return; fi
    action=$1
    shift
    case "$action" in
        help|-h|--help) usage; return ;;
        install)
            if [[ $# -gt 0 ]]; then
                [[ $# -eq 2 && "$1" == --hours ]] || fail 'Use install [--hours N].'
                hours=$2
            fi
            [[ "$hours" =~ ^[1-9][0-9]*$ && ${#hours} -le 4 ]] ||
                fail 'Hours must be an integer from 1 to 8760.'
            [[ "$hours" -le 8760 ]] || fail 'Hours must be an integer from 1 to 8760.'
            ;;
        status|run|pause|resume|uninstall)
            [[ $# -eq 0 ]] || fail "Unexpected arguments for $action."
            ;;
        *) fail "Unknown command: $action. Use help." ;;
    esac
    require_session
    case "$action" in
        install) install_command "$hours" ;;
        status) status_command ;;
        run)
            validate_installation
            /bin/sh -n "$app_dir/reconnect.sh" || fail 'The installed script has a syntax error.'
            is_loaded || fail 'The task is not loaded. Use resume first.'
            launchctl kickstart "$service"
            printf 'Run requested. Check the logs after about 15–20 seconds.\n'
            ;;
        pause) validate_installation; pause_command ;;
        resume)
            validate_installation
            load_task
            printf 'Task is enabled and loaded. No reconnect was requested.\n'
            ;;
        uninstall) uninstall_command ;;
    esac
}

configure_paths "$HOME"
if [[ "$BASH_SOURCE" == "$0" ]]; then
    main "$@"
fi
