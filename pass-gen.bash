#!/usr/bin/env bash

IFS=$'\n'

set +B -feuo pipefail
shopt -s lastpipe

# ---------------------- #
#       ENVIRONMENT      #
# ---------------------- #
readonly PASS_GEN_DATA_DIRS=(
    "${PASS_GEN_DATA_DIR:-}"
    "${XDG_DATA_HOME:-${HOME}/.local/share}/pass-gen"
    "/usr/share/pass-gen"
)

readonly PASS_GEN_ENTROPY_FILE="${PASS_GEN_ENTROPY_FILE:-/tmp/pass-gen.report}"


# ---------------------- #
#         GLOBALS        #
# ---------------------- #
unset ELEMENT_COUNT
unset ELEMENT_SEPARATOR

BATCH_COUNT=1
GENERATE_REPORT=no


# ---------------------- #
#          UTILS         #
# ---------------------- #
eprintf () {
    printf "${@}" >&2
}

error () {
    local MSG="${1}"

    eprintf 'pass-gen: %s\n' "${MSG}"
    exit 1
}

exprf () {
    local FORMAT="${1}"
    local EXPR="${2}"

    awk "BEGIN { printf \"${FORMAT}\", ${EXPR} }" /dev/null
}

hex_encode () {
    local STR="${1}"

    od -t x -A x <<< "${STR}" | tr -d '[:space:]'
}

quote () {
    local STR="${1}"

    STR="${STR//\"/\\\"}"
    STR="${STR//$'\n'/\\n}"

    printf '"%s"' "${STR}"
}

shell_quote () {
    local STR="${1}"

    STR="${STR//\'/\'\\\'\'}"
    STR="${STR//$'\n'/\'$\'\\n\'\'}"

    printf "'%s'" "${STR}"
}


# ---------------------- #
#         RANDOM         #
# ---------------------- #
SEEDS=()
SEEDS_LIMIT=50
SEEDS_EMPTY=1
SEEDS_CURSOR=0

random () {
    local VAR="${1}"
    local UPPER_BOUND="${2}"

    if (( SEEDS_EMPTY || SEEDS_CURSOR >= SEEDS_LIMIT )); then
        SEEDS_LIMIT=$(( SEEDS_LIMIT < 1600 ? SEEDS_LIMIT * 2 : SEEDS_LIMIT ))
        SEEDS=($(dd if=/dev/random count="${SEEDS_LIMIT}" bs=4 2>/dev/null | od -t u4 -w4 -A n))
        SEEDS_CURSOR=0
        SEEDS_EMPTY=0
    fi

    eval ${VAR}=$(( ${SEEDS[(( SEEDS_CURSOR++ ))]} % UPPER_BOUND ))
}


# ---------------------- #
#         ELEMENT        #
# ---------------------- #
declare -A POOL_WEIGHT=()
declare -A POOL_LENGTH=()

TOTAL_POOL_WEIGHT=0

read_pool () {
    local FILE="${1}"
    local WEIGHT="$(exprf '%d' "${2} * 100")"
    local POOL_NAME="ELEMENT_POOL_$(hex_encode "${FILE}")"

    if [ -v POOL_WEIGHT[${POOL_NAME}] ]; then
        TOTAL_POOL_WEIGHT=$(( TOTAL_POOL_WEIGHT + WEIGHT - ${POOL_WEIGHT[${POOL_NAME}]} ))

        POOL_WEIGHT[${POOL_NAME}]="${WEIGHT}"

        return 0
    fi

    TOTAL_POOL_WEIGHT=$(( TOTAL_POOL_WEIGHT + WEIGHT ))

    POOL_WEIGHT[${POOL_NAME}]="${WEIGHT}"

    eval ${POOL_NAME}="(\$(< ${FILE}))"

    eval POOL_LENGTH[${POOL_NAME}]="\${#${POOL_NAME}[@]}"
}

find_element_file () {
    local NAME="${1}"
    local DIR

    for DIR in "${PASS_GEN_DATA_DIRS[@]}"; do
        [ ! -d "${DIR}" ] && continue

        local FILE="${DIR}/datasets/${NAME}"

        if [ -r "${FILE}" ]; then
            printf '%s' "${FILE}"
            return 0
        fi
    done

    error "Missing required dataset file: \"${NAME}\""
}

read_element_file () {
    local NAME="${1}"
    local WEIGHT="${2}"
    local FILE

    FILE="$(find_element_file "${NAME}")"

    read_pool "${FILE}" "${WEIGHT}"
}

random_pool_name () {
    local VAR="${1}"
    local CUM_WEIGHT=0
    local RANDOM_WEIGHT
    local NAME

    random RANDOM_WEIGHT "${TOTAL_POOL_WEIGHT}"

    for NAME in "${!POOL_WEIGHT[@]}"; do
        CUM_WEIGHT=$(( CUM_WEIGHT + ${POOL_WEIGHT[${NAME}]} ))

        if (( RANDOM_WEIGHT < CUM_WEIGHT )); then
            eval ${VAR}='${NAME}'
            return 0
        fi
    done
}

random_pool_element () {
    local VAR="${1}"
    local POOL_NAME="${2}"
    local RANDOM_INDEX

    random RANDOM_INDEX "${POOL_LENGTH[${POOL_NAME}]}"

    eval ${VAR}="\${${POOL_NAME}[${RANDOM_INDEX}]}"
}


# ---------------------- #
#         REPORT         #
# ---------------------- #
readonly SECOND_BOUND=59
readonly MINUTE_BOUND=3599
readonly HOUR_BOUND=86399
readonly DAY_BOUND=31557599
readonly YEAR_BOUND=3155759999

get_time_unit () {
    local SECONDS="${1}"

    if [ ${#SECONDS} -gt 10 ] || (( SECONDS > YEAR_BOUND )); then
        printf century
    elif (( SECONDS > DAY_BOUND )); then
        printf year
    elif (( SECONDS > HOUR_BOUND )); then
        printf day
    elif (( SECONDS > MINUTE_BOUND )); then
        printf hour
    elif (( SECONDS > SECOND_BOUND )); then
        printf minute
    else
        printf second
    fi
}

format_unit () {
    local VALUE="${1}"
    local SINGULAR_UNIT="${2}"
    local PLURAL_UNIT="${3}"

    if  [ ${#VALUE} = 1 ] && [ "${VALUE}" -le 1 ]; then
        printf "%d %s" "${VALUE}" "${SINGULAR_UNIT}"
    elif [ ${#VALUE} -le 5 ]; then
        printf "%d %s" "${VALUE}" "${PLURAL_UNIT}"
    else
        printf "%.0e %s" "${VALUE}" "${PLURAL_UNIT}"
    fi
}

format_time () {
    local SECONDS="${1}"

    if [ "${SECONDS}" = +inf ] || [ ${#SECONDS} -gt 106 ]; then
        printf 'HEAT DEATH OF UNIVERSE'
    elif [ "${SECONDS}" = 0 ]; then
        printf 'less than a second'
    else
        case "$(get_time_unit "${SECONDS}")" in
            second)  format_unit "${SECONDS}" second seconds ;;
            minute)  format_unit "$(exprf '%d' "${SECONDS} / ${SECOND_BOUND}")" minute minutes ;;
            hour)    format_unit "$(exprf '%d' "${SECONDS} / ${MINUTE_BOUND}")" hour hours ;;
            day)     format_unit "$(exprf '%d' "${SECONDS} / ${HOUR_BOUND}")" day days ;;
            year)    format_unit "$(exprf '%d' "${SECONDS} / ${DAY_BOUND}")" year years ;;
            century) format_unit "$(exprf '%d' "${SECONDS} / ${YEAR_BOUND}")" century centuries ;;
        esac
    fi
}

format_entropy () {
    local ENTROPY="${1}"
    local SCALE="${2}"

    if [ "${ENTROPY}" = 0 ]; then
        printf 'none'
    else
        format_time "$(exprf '%d' "2 ^ ${ENTROPY} / ${SCALE}")"
    fi
}

calculate_entropy () {
    local ELEMENT_ENTROPY=0
    local POOL_NAME

    for POOL_NAME in "${!POOL_LENGTH[@]}"; do
        local LENGTH="${POOL_LENGTH[${POOL_NAME}]}"
        local WEIGHT="${POOL_WEIGHT[${POOL_NAME}]}"
        local ENTROPY=$(exprf '%f' "${WEIGHT} / ${TOTAL_POOL_WEIGHT} * log(${LENGTH}) / log(2)")

        ELEMENT_ENTROPY=$(exprf '%f' "${ELEMENT_ENTROPY} + ${ENTROPY}")
    done

    printf '%s' "${ELEMENT_ENTROPY}"
}

print_report () {
    local ELEMENT_ENTROPY="$(calculate_entropy)"
    local TOTAL_ENTROPY="$(exprf '%f' "${ELEMENT_ENTROPY} * ${ELEMENT_COUNT}")"

	eprintf "Entropy per element:       %.1f bits\n" "${ELEMENT_ENTROPY}"
	eprintf "Total entropy:             %.1f bits\n" "${TOTAL_ENTROPY}"
	eprintf "Guess times:\n"
	eprintf "  1 billion / second:      %s\n" "$(format_entropy "${TOTAL_ENTROPY}" 1e9)"
	eprintf "  1 quadrillion / second:  %s\n" "$(format_entropy "${TOTAL_ENTROPY}" 1e15)"
	eprintf "  1 sextillion / second:   %s\n" "$(format_entropy "${TOTAL_ENTROPY}" 1e21)"
    eprintf '=%.0s' $(seq "$(tput cols)")
    eprintf '\n'
}


# ---------------------- #
#          HELP          #
# ---------------------- #
print_help () {
    cat << EOF
Usage: pass-gen [OPTIONS]

Options:
  -p, --preset       Pick the settings from a predefined preset
  -f, --format       Set the password generation format
  -d, --dataset      Add a custom dataset to the format
  -s, --separator    Set the separator between password elements
  -n, --count        Set the number of elements to generate
  -b, --batch        Set the number of batches to generate
  -r, --report       Enable password strength reporting
  +r, --no-report    Disable password strength reporting
  -h, --help         Print this help message and exit

Presets:
  word               Preset for generating 6 word passphrases
  number             Preset for generating 6 random digits
  alpha              Preset for generating 20 random letters
  alnum              Preset for generating 20 random letters and digits
  complex            Preset for generating 20 random letters, digits and symbols

Bundled Datasets:
  lower              Dataset containing lowercase letters
  upper              Dataset containing uppercase letters
  digit              Dataset containing ASCII digits
  symbol             Dataset containing ASCII symbols
  word               Dataset containing common english words

Environment Variables:
  PASS_GEN_DATA_DIR  Path to a custom directory containing datasets

Examples:
  pass-gen -r
  pass-gen -p complex
  pass-gen -f digit:0.5,lower,upper -n 20
  pass-gen -d wordlist.txt -s " "
EOF
}


# ---------------------- #
#        ARGUMENTS       #
# ---------------------- #
expand_args () {
    local ARGS=()

    while [ -v 1 ]; do
        local ARG="${1}"; shift 1

        if [[ "${ARG}" =~ ^-[[:alnum:]] ]]; then
            # parse short options
            local LEN=${#ARG}
            local IDX

            for (( IDX = 1; IDX < LEN; IDX++ )); do
                local CHAR="${ARG:${IDX}:1}"

                ARGS+=("$(shell_quote "-${CHAR}")")

                case "${CHAR}" in
                    p | f | d | n | b | s)
                        if (( ++IDX < LEN )); then
                            ARGS+=("$(shell_quote "${ARG:${IDX}}")")
                        elif [ -v 1 ]; then
                            ARGS+=("$(shell_quote "${1}")")
                            shift 1
                        fi

                        break
                    ;;
                esac
            done
        elif [[ "${ARG}" =~ ^--[-_[:alnum:]]+$ ]]; then
            # handle long options
            ARGS+=("${ARG}")

            case "${ARG}" in
                --preset | --format | --dataset | --count | --batch | --separator)
                    if [ -v 1 ]; then
                        ARGS+=("$(shell_quote "${1}")")
                        shift 1
                    fi
                ;;
            esac
        elif [[ "${ARG}" =~ ^(--[-_[:alnum:]]+)=(.+)$ ]]; then
            # parse option=value pairs
            ARGS+=(
                "${BASH_REMATCH[1]}"
                "$(shell_quote "${BASH_REMATCH[2]}")"
            )
        else
            # handle values
            ARGS+=("$(shell_quote "${ARG}")")
        fi
    done

    printf '%s' "${ARGS[*]}"
}

validate_missing_arg () {
    if [ ! -v 2 ]; then
        error "Missing argument to option $(quote "${1}")"
    elif [[ "${2}" =~ ^[[:blank:]]*$ ]]; then
        error "Empty argument to option $(quote "${1}"): $(quote "${2}")"
    fi
}

parse_args () {
    # expand arguments
    local ARGS; ARGS="$(expand_args "${@}")"

    eval set -- ${ARGS}

    # check for help flag
    local ARG
    for ARG in "${@}"; do
        if [ "${ARG}" = -h ] || [ "${ARG}" = --help ]; then
            print_help
            exit 0
        fi
    done

    # parse arguments
    while [ -v 1 ]; do
        case "${1}" in
            -p | --preset)
                validate_missing_arg "${@}"

                case "${2}" in
                    word)
                        [ ! -v ELEMENT_COUNT ] && ELEMENT_COUNT=6
                        [ ! -v ELEMENT_SEPARATOR ] && ELEMENT_SEPARATOR=" "

                        read_element_file word 1
                    ;;
                    number)
                        [ ! -v ELEMENT_COUNT ] && ELEMENT_COUNT=6
                        [ ! -v ELEMENT_SEPARATOR ] && ELEMENT_SEPARATOR=""

                        read_element_file digit 1
                    ;;
                    alpha)
                        [ ! -v ELEMENT_COUNT ] && ELEMENT_COUNT=20
                        [ ! -v ELEMENT_SEPARATOR ] && ELEMENT_SEPARATOR=""

                        read_element_file lower 1
                        read_element_file upper 1
                    ;;
                    alnum)
                        [ ! -v ELEMENT_COUNT ] && ELEMENT_COUNT=20
                        [ ! -v ELEMENT_SEPARATOR ] && ELEMENT_SEPARATOR=""

                        read_element_file lower 1
                        read_element_file upper 1
                        read_element_file digit 1
                    ;;
                    complex)
                        [ ! -v ELEMENT_COUNT ] && ELEMENT_COUNT=20
                        [ ! -v ELEMENT_SEPARATOR ] && ELEMENT_SEPARATOR=""

                        read_element_file lower 1
                        read_element_file upper 1
                        read_element_file digit 1
                        read_element_file symbol 1
                    ;;
                    *) error "Invalid preset: $(quote "${2}")" ;;
                esac

                shift 2
            ;;
            -f | --format)
                validate_missing_arg "${@}"

                [ ! -v ELEMENT_SEPARATOR ] && ELEMENT_SEPARATOR=""

                local NAME WEIGHT FORMAT="${2},"

                while [[ "${FORMAT}" =~ ^([^,]*),(.*)$ ]]; do
                    NAME="${BASH_REMATCH[1]}"
                    FORMAT="${BASH_REMATCH[2]}"
                    WEIGHT=1

                    if [[ "${NAME}" =~ ^(.*):(([0-9]+\.?[0-9]*)|(\.?[0-9]+))$ ]]; then
                        NAME="${BASH_REMATCH[1]}"
                        WEIGHT="${BASH_REMATCH[2]}"
                    fi

                    if [[ "${NAME}" =~ ^[[:blank:]]*$ ]]; then
                        error "Missing dataset name in format: $(quote "${2}")"
                    fi

                    read_element_file "${NAME}" "${WEIGHT}"
                done

                shift 2
            ;;
            -d | --dataset)
                validate_missing_arg "${@}"

                [ ! -v ELEMENT_SEPARATOR ] && ELEMENT_SEPARATOR=""

                local FILE="${2}"
                local WEIGHT=1

                if [[ "${FILE}" =~ ^(.*):(([0-9]+\.?[0-9]*)|(\.?[0-9]+))$ ]]; then
                    FILE="${BASH_REMATCH[1]}"
                    WEIGHT="${BASH_REMATCH[2]}"
                fi

                if [[ "${FILE}" =~ ^[[:blank:]]*$ ]]; then
                    error "Missing dataset filepath: $(quote "${2}")"
                fi

                if [ ! -r "${FILE}" ]; then
                    error "Unreadable dataset file: $(quote "${FILE}")"
                fi

                read_pool "${FILE}" "${WEIGHT}"
                shift 2
            ;;
            -n | --count)
                validate_missing_arg "${@}"

                if [[ ! "${2}" =~ ^0*([1-9][0-9]*)$ ]]; then
                    error "Invalid argument for element count: $(quote "${2}")"
                fi

                ELEMENT_COUNT="${BASH_REMATCH[1]}"
                shift 2
            ;;
            -b | --batch)
                validate_missing_arg "${@}"

                if [[ ! "${2}" =~ ^0*([1-9][0-9]*)$ ]]; then
                    error "Invalid argument for batch count: $(quote "${2}")"
                fi

                BATCH_COUNT="${BASH_REMATCH[1]}"
                shift 2
            ;;
            -s | --separator)
                if [ ! -v 2 ]; then
                    error "Missing argument to option $(quote "${1}")"
                fi

                ELEMENT_SEPARATOR="${2}"
                shift 2
            ;;
            -r | --report)
                GENERATE_REPORT=yes
                shift 1
            ;;
            +r | --no-report)
                GENERATE_REPORT=no
                shift 1
            ;;
            --private:calculate_entropy)
                GENERATE_REPORT=private:calculate_entropy
                shift 1
            ;;
            -*) error "Invalid flag: $(quote "${1}")" ;;
            *)  error "Invalid argument: $(quote "${1}")" ;;
        esac
    done

    # use settings from words preset as default
    if [ ${#POOL_LENGTH[@]} = 0 ]; then
        read_element_file word 1
    fi

    if [ ! -v ELEMENT_COUNT ]; then
        ELEMENT_COUNT=6
    fi

    if [ ! -v ELEMENT_SEPARATOR ]; then
        ELEMENT_SEPARATOR=" "
    fi
}


# ---------------------- #
#          MAIN          #
# ---------------------- #
main () {
    # parse arguments
    parse_args "${@}"

    # generate report
    case "${GENERATE_REPORT}" in
        private:calculate_entropy)
            calculate_entropy > "${PASS_GEN_ENTROPY_FILE}"
        ;;
        yes) print_report ;;
    esac

    # generate password
    local BX EX POOL_NAME ELEMENT

    for (( BX = 1; BX <= BATCH_COUNT; BX++ )); do
        for (( EX = 1; EX <= ELEMENT_COUNT; EX++ )); do
            random_pool_name POOL_NAME
            random_pool_element ELEMENT "${POOL_NAME}"

            printf '%s' "${ELEMENT}"

            if (( EX < ELEMENT_COUNT )); then
                printf '%s' "${ELEMENT_SEPARATOR}"
            fi
        done

        if (( BATCH_COUNT > 1 )); then
            printf '\n'
        fi
    done
}

main "${@}"
