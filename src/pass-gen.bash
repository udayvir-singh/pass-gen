#!/usr/bin/env bash

set +x -euo pipefail

# ---------------------- #
#         UTILS          #
# ---------------------- #
error () {
	echo "pass-gen: ${1}" >&2
	exit 1
}

verify_exists () {
	local ARG=${1:-}
	local VAL=${2:-}

	if [ -z "${VAL}" ]; then
		error "missing argument to ${ARG}"
	fi
}

verify_integer () {
	local ARG=${1}
	local VAL=${2}

	if [[ ! "${VAL}" =~ ^[0-9]+$ ]] || [ "${VAL}" -lt 1 ]; then
		error "invalid argument to ${ARG}, expected integer got '${VAL}'"
	fi
}


# ---------------------- #
#         REPORT         #
# ---------------------- #
print_report () {
	local COLUMNS=$(tput cols 2>/dev/null || echo 60)

	awk -v POOL=${1} -v COUNT=${2} -v COLUMNS=${COLUMNS} '
		function tounit(x, unit) {
			if (x < 1e9)
				return sprintf("%.0f %s", x, unit)
			else
				return sprintf("%.0e %s", x, unit)
		}

		function format_time(t) {
			minute  = 60
			hour    = minute * 60
			day     = hour * 24
			year    = day * 365.25
			century = year * 100

			if (t < 1)
				return "less than a second"
			else if (t < minute)
				return tounit(t, "seconds")
			else if (t < hour)
				return tounit(t / minute, "minutes")
			else if (t < day)
				return tounit(t / hour, "hours")
			else if (t < year)
				return tounit(t / day, "days")
			else if (t < century)
				return tounit(t / year, "years")
			else
				return tounit(t / century, "centuries")
		}

		{
			entropy = log(POOL) / log(2)
			total_entropy = entropy * COUNT

			printf "entropy per word:           %.1f bits\n", entropy
			printf "total entropy:              %.f bits\n", total_entropy
			printf "guess times:\n"
			printf "  1 quadrillion / second:   %s\n", format_time(2 ** (total_entropy - 51))
			printf "  1 quintillion / second:   %s\n", format_time(2 ** (total_entropy - 61))
			printf "  1 sextillion / second:    %s\n", format_time(2 ** (total_entropy - 71))

			for (i = 0; i < COLUMNS; i++) {
				printf "-"
			}
			printf "\n"
		}
	' <<< '' >&2
}


# ---------------------- #
#          HELP          #
# ---------------------- #
print_help () {
	echo "Usage: pass-gen [OPTIONS]

Options:
  -w, --word N        generate password of N words
  -s, --sep STRING    set STRING as the word separator
  -f, --file PATH     set PATH as the wordlist
  -r, --report        print report of password strength
  -h, --help          display this help and exit

Examples:
  pass-gen -w 8 -s '-'
  pass-gen -r"

	exit 0
}


# ---------------------- #
#       ARGUMENTS        #
# ---------------------- #
WORD_COUNT=6
WORD_SEP=" "
WORD_FILE="${HOME}/.local/lib/pass-gen/wordlist.txt"
REPORT=0

while [ -v 1 ]; do
	case "${1}" in
		-w | --word)
			[ ! -v 2 ] && error "missing argument to ${1}"
			verify_integer "${1}" "${2}"

			WORD_COUNT=${2}
			shift 2
		;;
		-s | --sep)
			[ ! -v 2 ] && error "missing argument to ${1}"

			WORD_SEP=${2}
			shift 2
		;;
		-f | --file)
			[ ! -v 2 ] && error "missing argument to ${1}"

			WORD_FILE=${2}
			shift 2
		;;
		-r | --report)
			REPORT=1
			shift 1
		;;
		-h | --help) print_help ;;
		*) error "invalid option ${1}" ;;
	esac
done


# ---------------------- #
#          MAIN          #
# ---------------------- #
main () {
	readarray -t WORDS < "${WORD_FILE}"

	if [ "${REPORT}" = 1 ]; then
		print_report "${#WORDS[@]}" "${WORD_COUNT}"
	fi

	local WORDS_MAX=$(( ${#WORDS[@]} - 1 ))

	for ((i = 1; i <= WORD_COUNT; i++)); do
		local IDX=$(shuf -n 1 -i 0-${WORDS_MAX})

		printf "%s" "${WORDS[$IDX]}"

		if [ "${WORD_COUNT}" != "${i}" ]; then
			printf "%s" "${WORD_SEP}"
		fi
	done
}

main
