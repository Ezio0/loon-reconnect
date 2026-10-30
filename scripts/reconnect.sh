#!/bin/sh

result=0

send_action() {
    if /usr/bin/open -g "$1"; then
        /usr/bin/printf '%s sent %s\n' \
            "$(/bin/date '+%Y-%m-%d %H:%M:%S %z')" "$1"
    else
        code=$?
        /usr/bin/printf '%s failed %s (open exit %s)\n' \
            "$(/bin/date '+%Y-%m-%d %H:%M:%S %z')" "$1" "$code" >&2
        result=1
    fi
}

# 即使关闭调用失败，也继续尝试开启。
send_action 'loon://off'
/bin/sleep 3
send_action 'loon://on'
/bin/sleep 10
send_action 'loon://update?sub=all'

exit "$result"
