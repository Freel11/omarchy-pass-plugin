#!/bin/bash
STORE="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
find "$STORE" -type f -name '*.gpg' -printf '%T@ %p\n' |
	sort -rn |
	cut -d' ' -f2- |
	sed "s#^${STORE}/##; s#\.gpg\$##"
