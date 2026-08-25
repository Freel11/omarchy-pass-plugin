#!/bin/bash
# args: <action> <entry>
action="$1"
entry="$2"
case "$action" in
copy) pass show -c "$entry" && notify-send "Pass" "Copied $entry to clipboard" ;;
type) pass show "$entry" | head -1 | tr -d '\n' | wtype - && notify-send "Pass" "Typed $entry" ;;
otp)  pass otp -c "$entry" && notify-send "Pass" "Copied OTP for $entry to clipboard" ;;
esac
