#!/usr/bin/env bash

IFS=$'\n'

set +B -feuo pipefail
shopt -s lastpipe

# ---------------------- #
#       ENVIRONMENT      #
# ---------------------- #
readonly PASS_GEN_SCRIPT="${PASS_GEN_SCRIPT:-pass-gen}"

declare -rx PASS_GEN_ENTROPY_FILE="${PASS_GEN_ENTROPY_FILE:-/tmp/pass-gen.report}"


# ---------------------- #
#         GLOBALS        #
# ---------------------- #
declare -A REFERENCES=()
REFERENCE_COUNT=0

OUTPUT=""
OUTPUT_FORMAT=""
OUTPUT_ARGUMENTS=()

ENTROPY_INFO=()
GENERATE_REPORT=no


# ---------------------- #
#          UTILS         #
# ---------------------- #
eprintf () {
    printf "${@}" >&2
}

error () {
    local MSG="${1}"

    eprintf 'pass-genf: %s\n' "${MSG}"
    exit 1
}

exprf () {
    local FORMAT="${1}"
    local EXPR="${2}"

    awk "BEGIN { printf \"${FORMAT}\", ${EXPR} }" /dev/null
}

quote () {
    local STR="${1}"

    STR="${STR//\"/\\\"}"
    STR="${STR//$'\n'/\\n}"

    printf '"%s"' "${STR}"
}

capitalize () {
    local STR="${1}"

    STR="${STR,,}"
    STR="${STR^}"

    printf '%s' "${STR}"
}

titlize () {
    local STR="${1}"

    while [[ "${STR}" =~ ^([^[:alpha:]]*)([[:alpha:]]+)(.*)$ ]]; do
        STR="${BASH_REMATCH[-1]}"
        printf '%s%s' "${BASH_REMATCH[1]}" "$(capitalize "${BASH_REMATCH[2]}")"
    done

    printf '%s' "${STR}"
}

set_case () {
    local CASE="${1}"
    local STR="${2}"

    case "${CASE}" in
        l) printf '%s' "${STR,,}" ;;
        u) printf '%s' "${STR^^}" ;;
        c) capitalize "${STR}" ;;
        t) titlize "${STR}" ;;
    esac
}


# ---------------------- #
#         OUTPUT         #
# ---------------------- #
pop_output_arg () {
    local VAR="${1}"
    local NAME="${2}"

    if [ ! -v OUTPUT_ARGUMENTS[0] ]; then
        error "Missing required argument for ${NAME}"
    fi

    eval ${VAR}='${OUTPUT_ARGUMENTS[0]}'

    OUTPUT_ARGUMENTS=("${OUTPUT_ARGUMENTS[@]:1}")
}

substitute_string () {
    local VAR="${1}"
    local LEVEL="${2}"
    local OPTIONS="${3}"
    local REFERENCE=$(( ++REFERENCE_COUNT ))

    # handle level based variables
    local OP_SEP NAME

    case "${LEVEL}" in
        0) OP_SEP="," ;;
        1) OP_SEP=";" ;;
        2) OP_SEP=":" ;;
        3) OP_SEP="!" ;;
        *) error "Cannot have more then 3 levels of nesting for %s" ;;
    esac

    OPTIONS+="${OP_SEP}"

    if [ "${LEVEL}" = 0 ]; then
        NAME="%s"
    else
        NAME="nested(${LEVEL}) %s"
    fi

    # pop value from arguments
    local VALUE=""
    pop_output_arg VALUE "${NAME}"

    # parse options
    local CASE_OPTION=""
    local OPTION OPTION_NAME OPTION_ARG

    while [[ "${OPTIONS}" =~ ^(([^${OP_SEP}=]*)(=[^${OP_SEP}]*)?)${OP_SEP}+(.*)$ ]]; do
        OPTIONS="${BASH_REMATCH[-1]}"
        OPTION="${BASH_REMATCH[1]}"
        OPTION_NAME="${BASH_REMATCH[2]}"
        OPTION_ARG="${BASH_REMATCH[3]}"

        # skip empty option
        if [[ "${OPTION}" =~ ^[[:blank:]]*$ ]]; then
            continue
        fi

        # evaluate option
        case "${OPTION_NAME}" in
            l | u | c | t)
                if [ -n "${OPTION_ARG}" ]; then
                    error "Invalid argument after option $(quote "${OPTION_NAME}") for ${NAME}"
                fi

                CASE_OPTION="${OPTION_NAME}"
            ;;
            *) error "Invalid option $(quote "${OPTION}") for ${NAME}" ;;
        esac
    done

    # set value case
    if [ -n "${CASE_OPTION}" ]; then
        VALUE="$(set_case "${CASE_OPTION}" "${VALUE}")"
    fi

    # store value in references
    REFERENCES[${REFERENCE}]="${VALUE}"

    # set value in given var
    eval ${VAR}='${VALUE}'
}

substitute_password () {
    local VAR="${1}"
    local LEVEL="${2}"
    local OPTIONS="${3}"
    local FORMAT_FLAG="${4}"
    local REFERENCE=$(( ++REFERENCE_COUNT ))

    # handle level based variables
    local OP_SEP NOP_LB NOP_RB NAME

    case "${LEVEL}" in
        0) OP_SEP=','; NOP_LB='\['; NOP_RB=']' ;;
        1) OP_SEP=';'; NOP_LB='\('; NOP_RB=')' ;;
        2) OP_SEP=':'; NOP_LB='<'; NOP_RB='>' ;;
        *) error "Cannot have more then 2 levels of nesting for %${FORMAT_FLAG: -1}" ;;
    esac

    OPTIONS+="${OP_SEP}"

    if [ "${LEVEL}" = 0 ]; then
        NAME="%${FORMAT_FLAG: -1}"
    else
        NAME="nested(${LEVEL}) %${FORMAT_FLAG: -1}"
    fi

    # pop format from arguments
    local FORMAT_FLAGS=()
    local FORMAT=""

    pop_output_arg FORMAT "${NAME}"

    FORMAT_FLAGS+=("${FORMAT_FLAG}" "${FORMAT}")

    # parse options
    local CASE_OPTION=""
    local SEP_OPTION=""
    local COUNT_OPTION=6
    local OPTION OPTION_NAME OPTION_ARG_OUTER OPTION_ARG_BUFFER

    while [[ "${OPTIONS}" =~ ^(([^${OP_SEP}=]*)(=([^${OP_SEP}]*))?)${OP_SEP}+(.*)$ ]]; do
        OPTIONS="${BASH_REMATCH[-1]}"
        OPTION="${BASH_REMATCH[1]}"
        OPTION_NAME="${BASH_REMATCH[2]}"
        OPTION_ARG_OUTER="${BASH_REMATCH[3]}"
        OPTION_ARG_BUFFER="${BASH_REMATCH[4]}"

        # skip empty option
        if [[ "${OPTION}" =~ ^[[:blank:]]*$ ]]; then
            continue
        fi

        # parse option argument
        local OPTION_ARG=""
        local NESTED_ESCAPE NESTED_OPTIONS_OUTER NESTED_OPTIONS

        while [[ "${OPTION_ARG_BUFFER}" =~ ^([^%]*)%([0-9]+|.)(${NOP_LB}([^${NOP_RB}]*)${NOP_RB})?(.*)$ ]]; do
            OPTION_ARG_BUFFER="${BASH_REMATCH[-1]}"
            OPTION_ARG+="${BASH_REMATCH[1]}"
            NESTED_ESCAPE="${BASH_REMATCH[2]}"
            NESTED_OPTIONS_OUTER="${BASH_REMATCH[3]}"
            NESTED_OPTIONS="${BASH_REMATCH[4]}"

            # handle nested escape sequences
            case "${NESTED_ESCAPE}" in
                s | f | d | [0-9]*)
                    local NVAR="NESTED_VALUE_${LEVEL}"
                    local ${NVAR}

                    case "${NESTED_ESCAPE}" in
                        s) substitute_string ${NVAR} $(( LEVEL + 1 )) "${NESTED_OPTIONS}" ;;
                        f) substitute_password ${NVAR} $(( LEVEL + 1 )) "${NESTED_OPTIONS}" -f ;;
                        d) substitute_password ${NVAR} $(( LEVEL + 1 )) "${NESTED_OPTIONS}" -d ;;
                        *) substitute_reference ${NVAR} $(( LEVEL + 1 )) "${NESTED_OPTIONS}" "${NESTED_ESCAPE}" ;;
                    esac

                    eval OPTION_ARG+="\${${NVAR}}"
                ;;
                % | { | [ | \( | \<)
                    OPTION_ARG+="${NESTED_ESCAPE}"
                    OPTION_ARG_BUFFER+="${NESTED_OPTIONS_OUTER}"
                ;;
                *)
                    error "Invalid escape sequence: %${NESTED_ESCAPE}"
                ;;
            esac
        done

        OPTION_ARG+="${OPTION_ARG_BUFFER}"

        # evaluate options
        case "${OPTION_NAME}" in
            +f | +d)
                if [ -n "${OPTION_ARG_OUTER}" ]; then
                    error "Invalid argument after option $(quote "${OPTION_NAME}") for ${NAME}"
                fi

                local FORMAT=""

                pop_output_arg FORMAT "${OPTION_NAME}"

                FORMAT_FLAGS+=("-${OPTION_NAME:1}" "${FORMAT}")
            ;;
            l | u | c | t)
                if [ -n "${OPTION_ARG_OUTER}" ]; then
                    error "Invalid argument after option $(quote "${OPTION_NAME}") for ${NAME}"
                fi

                CASE_OPTION="${OPTION_NAME}"
            ;;
            s)
                if [ -z "${OPTION_ARG_OUTER}" ]; then
                    error "Missing argument after option $(quote "${OPTION_NAME}") for ${NAME}"
                fi

                SEP_OPTION="${OPTION_ARG}"
            ;;
            n)
                if [ -z "${OPTION_ARG}" ]; then
                    error "Missing argument after option $(quote "${OPTION_NAME}") for ${NAME}"
                fi

                COUNT_OPTION="${OPTION_ARG}"
            ;;
            *) error "Invalid option $(quote "${OPTION}") for ${NAME}" ;;
        esac
    done

    # generate command
    local CMD=("${PASS_GEN_SCRIPT}" "${FORMAT_FLAGS[@]}" -n "${COUNT_OPTION}" -s "${SEP_OPTION}")

    if [ "${GENERATE_REPORT}" = yes ]; then
        CMD+=(--private:calculate_entropy)
    fi

    # get value
    local VALUE; VALUE="$("${CMD[@]}")"

    # set value case
    if [ -n "${CASE_OPTION}" ]; then
        VALUE="$(set_case "${CASE_OPTION}" "${VALUE}")"
    fi

    # store value in references
    REFERENCES[${REFERENCE}]="${VALUE}"

    # set value in given var
    eval ${VAR}='${VALUE}'

    # push entropy information
    if [ "${GENERATE_REPORT}" = yes ]; then
        ENTROPY_INFO+=(
            "${FORMAT} (n=${COUNT_OPTION})"
            "$(exprf '%f' "${COUNT_OPTION} * $(< "${PASS_GEN_ENTROPY_FILE}")")"
        )
    fi
}

substitute_reference () {
    local VAR="${1}"
    local LEVEL="${2}"
    local OPTIONS="${3}"
    local RAW_REFERENCE="${4}"
    local NAME="%${RAW_REFERENCE}"

    # handle level based variables
    local OP_SEP

    case "${LEVEL}" in
        0) OP_SEP="," ;;
        1) OP_SEP=";" ;;
        2) OP_SEP=":" ;;
        3) OP_SEP="!" ;;
        *) error "Cannot have more then 3 levels of nesting for ${NAME}" ;;
    esac

    OPTIONS+="${OP_SEP}"

    # parse raw reference
    if [[ ! "${RAW_REFERENCE}" =~ ^0*([1-9][0-9]*)$ ]]; then
        error "Invalid reference: ${NAME}"
    fi

    local REFERENCE="${BASH_REMATCH[1]}"

    # validate reference
    if (( REFERENCE > REFERENCE_COUNT )); then
        error "Unknown reference: ${NAME}"
    fi

    if [ ! -v REFERENCES[${REFERENCE}] ]; then
        error "Unevaluated reference: ${NAME}"
    fi

    # parse options
    local CASE_OPTION=""
    local OPTION OPTION_NAME OPTION_ARG

    while [[ "${OPTIONS}" =~ ^(([^${OP_SEP}=]*)(=[^${OP_SEP}]*)?)${OP_SEP}+(.*)$ ]]; do
        OPTIONS="${BASH_REMATCH[-1]}"
        OPTION="${BASH_REMATCH[1]}"
        OPTION_NAME="${BASH_REMATCH[2]}"
        OPTION_ARG="${BASH_REMATCH[3]}"

        # skip empty option
        if [[ "${OPTION}" =~ ^[[:blank:]]*$ ]]; then
            continue
        fi

        # evaluate option
        case "${OPTION_NAME}" in
            l | u | c | t)
                if [ -n "${OPTION_ARG}" ]; then
                    error "Invalid argument after option $(quote "${OPTION_NAME}") for ${NAME}"
                fi

                CASE_OPTION="${OPTION_NAME}"
            ;;
            *) error "Invalid option $(quote "${OPTION}") for ${NAME}" ;;
        esac
    done

    # get value
    local VALUE="${REFERENCES[${REFERENCE}]}"

    # set value case
    if [ -n "${CASE_OPTION}" ]; then
        VALUE="$(set_case "${CASE_OPTION}" "${VALUE}")"
    fi

    # set value in given var
    eval ${VAR}='${VALUE}'
}

gen_output () {
    local ESCAPE OPTIONS_OUTER OPTIONS_INNER SEQ_VALUE

    while [[ "${OUTPUT_FORMAT}" =~ ^([^%]*)%([0-9]+|.)(\{([^\}]*)\})?(.*)$ ]]; do
        OUTPUT_FORMAT="${BASH_REMATCH[-1]}"
        OUTPUT+="${BASH_REMATCH[1]}"
        ESCAPE="${BASH_REMATCH[2]}"
        OPTIONS_OUTER="${BASH_REMATCH[3]}"
        OPTIONS_INNER="${BASH_REMATCH[4]}"
        SEQ_VALUE=""

        case "${ESCAPE}" in
            s)
                substitute_string SEQ_VALUE 0 "${OPTIONS_INNER}"
            ;;
            f)
                substitute_password SEQ_VALUE 0 "${OPTIONS_INNER}" -f
            ;;
            d)
                substitute_password SEQ_VALUE 0 "${OPTIONS_INNER}" -d
            ;;
            [0-9]*)
                substitute_reference SEQ_VALUE 0 "${OPTIONS_INNER}" "${ESCAPE}"
            ;;
            % | { | [ | \( | \<)
                SEQ_VALUE="${ESCAPE}"
                OUTPUT_FORMAT+="${OPTIONS_OUTER}"
            ;;
            *)
                error "Invalid escape sequence: %${ESCAPE}"
            ;;
        esac

        OUTPUT+="${SEQ_VALUE}"
    done

    OUTPUT+="${OUTPUT_FORMAT}"
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

    if [ "${VALUE}" = 1 ]; then
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

print_report () {
    # calculate max message width
    local MAX_WIDTH=25
    local IDX

    for (( IDX = 0; IDX < ${#ENTROPY_INFO[@]}; IDX += 2 )); do
        local WIDTH=${#ENTROPY_INFO[${IDX}]}

        if [ "${WIDTH}" -gt "${MAX_WIDTH}" ]; then
            MAX_WIDTH="${WIDTH}"
        fi
    done

    # print entropy messages
    local TOTAL_ENTROPY=0
    local IDX

    for (( IDX = 0; IDX < ${#ENTROPY_INFO[@]}; IDX += 2 )); do
        local NAME="${ENTROPY_INFO[${IDX}]}"
        local ENTROPY="${ENTROPY_INFO[(( IDX + 1 ))]}"

        TOTAL_ENTROPY="$(exprf '%f' "${TOTAL_ENTROPY} + ${ENTROPY}")"

        eprintf "%-${MAX_WIDTH}s  %.1f bits\n" "Entropy for ${NAME}:" "${ENTROPY}"
    done

    eprintf "%-${MAX_WIDTH}s  %.1f bits\n" "Total entropy:" "${TOTAL_ENTROPY}"

    # print guess times
	eprintf "Guess times:\n"
	eprintf "%-${MAX_WIDTH}s  %s\n" "  1 billion / second:"     "$(format_entropy "${TOTAL_ENTROPY}" 1e9)"
	eprintf "%-${MAX_WIDTH}s  %s\n" "  1 quadrillion / second:" "$(format_entropy "${TOTAL_ENTROPY}" 1e15)"
	eprintf "%-${MAX_WIDTH}s  %s\n" "  1 sextillion / second:"  "$(format_entropy "${TOTAL_ENTROPY}" 1e21)"

    # print report separator
    eprintf '=%.0s' $(seq "$(tput cols)")
    eprintf '\n'
}


# ---------------------- #
#          HELP          #
# ---------------------- #
print_help () {
    cat << EOF
pass-genf [OPTIONS] -- FORMAT [ARGUMENTS]

Options:
  -r, --report     Enable password strength reporting
  +r, --no-report  Disable password strength reporting
  -h, --help       Print this help message and exit

Environment Variables:
  PASS_GEN_SCRIPT  Path to the pass-gen bash script

Examples:
  pass-genf '%f' lower,upper
  pass-genf '%f{s=-}-%f' word digit
  pass-genf '%f{t,n=4,s=%f[n=1]}%2%f' word symbol digit
EOF
}


# ---------------------- #
#        ARGUMENTS       #
# ---------------------- #
parse_args () {
    # parse arguments
    while [ -v 1 ]; do
        case "${1}" in
            -h | --help)
                print_help
                exit 0
            ;;
            -r | --report)
                GENERATE_REPORT=yes
                shift 1
            ;;
            +r | --no-report)
                GENERATE_REPORT=no
                shift 1
            ;;
            *)
                [ "${1}" == -- ] && shift 1

                if [ -v 1 ]; then
                    OUTPUT_FORMAT="${1}"; shift 1
                    OUTPUT_ARGUMENTS=("${@}")
                    return 0
                fi
            ;;
        esac
    done

    # handle missing format
    error "Missing output format descriptor"
}


# ---------------------- #
#          MAIN          #
# ---------------------- #
main () {
    # validate environment
    if ! command -v "${PASS_GEN_SCRIPT}" &>/dev/null; then
        error "Invalid executable in PASS_GEN_SCRIPT: $(quote "${PASS_GEN_SCRIPT}")"
    fi

    # parse arguments
    parse_args "${@}"

    # generate output
    gen_output

    # generate report
    if [ "${GENERATE_REPORT}" = yes ]; then
        print_report
    fi

    # print output
    printf '%s' "${OUTPUT}"
}

main "${@}"
