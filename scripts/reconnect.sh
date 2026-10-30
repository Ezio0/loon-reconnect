#!/bin/sh

result=0

send_action() {
    if /usr/bin/open -g -j "$1"; then
        /usr/bin/printf '%s sent %s\n' \
            "$(/bin/date '+%Y-%m-%d %H:%M:%S %z')" "$1"
    else
        code=$?
        /usr/bin/printf '%s failed %s (open exit %s)\n' \
            "$(/bin/date '+%Y-%m-%d %H:%M:%S %z')" "$1" "$code" >&2
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

# 即使关闭调用失败，也继续尝试开启。
send_action 'loon://off'
/bin/sleep 3
send_action 'loon://on'
/bin/sleep 10
send_action 'loon://update?sub=all'
/bin/sleep 2
hide_loon

exit "$result"
