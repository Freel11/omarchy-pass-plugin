#!/bin/bash
# args: <name> <value>
name="$1"
value="$2"
printf '%s\n' "$value" | pass insert -f -m "$name" && notify-send "Pass" "Added $name"
