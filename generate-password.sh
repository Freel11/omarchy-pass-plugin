#!/bin/bash
# args: <length: 1-128> <include-symbols: true|false>
set -u

if [[ $# -ne 2 ]]; then
	printf 'Usage: generate-password.sh <length: 1-128> <include-symbols: true|false>\n' >&2
	exit 2
fi

if [[ ! $1 =~ ^[0-9]{1,3}$ ]]; then
	printf 'Password length must be between 1 and 128.\n' >&2
	exit 2
fi

length=$((10#$1))
if (( length < 1 || length > 128 )); then
	printf 'Password length must be between 1 and 128.\n' >&2
	exit 2
fi

case "$2" in
true) characters='[:alnum:][:punct:]' ;;
false) characters='[:alnum:]' ;;
*)
	printf 'Include-symbols must be true or false.\n' >&2
	exit 2
	;;
esac

if ! IFS= read -r -N "$length" password < <(LC_ALL=C tr -dc "$characters" < /dev/urandom); then
	printf 'Could not generate a password from /dev/urandom.\n' >&2
	exit 1
fi

printf '%s\n' "$password"
