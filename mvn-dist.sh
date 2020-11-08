#!/usr/bin/env bash

DEBUG=0
### Functions
declare -f move_cursor_up
declare -f move_cursor_down
declare -f move_cursor_forward
declare -f move_cursor_backward
declare -f save_cursor_position
declare -f recall_cursor_position
declare -f delete_until_eol

### Associative arrays
declare -A options

### Regular, boring arrays
declare -a error_list=()
declare -a order=()
declare -a applications_from_cli_array=()
declare -a applications_from_config_array=()
declare -a application_difference_array=()

### Strings
declare ERROR_MSG=""
declare MVN_DIST_LOG=""
declare MVN_DIST_TMP_FILE=""
declare MVN_BINARY=""
declare config_app=""
declare build_profile=""
declare log="/tmp/mvn-dist.log"
declare chosen_applications=
declare path=.
declare application_path=""
declare absolute_path=""
declare application=""
declare applications_cfg="applications.cfg"
declare settings_cfg="settings.cfg"
declare mvn_dist_home="${HOME}/.mvn-dist"
declare pretty_print=""
declare available_options_string=""
declare specified_modules=""
declare check_diff_application=""
declare parsed_line=""

# From strings.sh, declare to satisfy syntax validation
declare NO_COLOUR=""
declare RED=""
declare GREEN=""
declare BLUE=""
declare BOLD=""
declare BLINK=""
declare UNKNOWN_PROFILE=""
declare BUILD_FAILURE=""
declare PERMISSIONS=""
declare NOT_FOUND=""
declare INVALID_PATH=""
declare NO_APPLICATIONS=""
declare USAGE=""
declare FIX=""
declare HELP=""

### Integers
declare -i START_TIME=$SECONDS
declare -i LOG_TAIL_LENGTH
declare -i MAX_TERMINAL_WIDTH
declare -i MIN_TERMINAL_WIDTH
declare -i terminal_width=80
declare -i flag_length=0
declare -i miscellaneous_text_length=8
declare -i error_count=0
declare -i build_count=0
declare -i pid

### Boolean Simulator
declare -i ON_WINDOWS=0
declare -i verbose=0
declare -i force=0
declare -i continue=0
declare -i split_log=0
declare -i skip_notification=0

# Debug
debug() {
    if [[ "${DEBUG}" -eq 1 ]]; then
        array=( "${@}" )
        for i in "${!array[@]}"; do
            printf "%s\\n" "${array[${i}]}"
        done
    fi
}

### Check for OS
check_for_windows() {
    OPERATING_SYSTEM=$( env | grep 'OS=' | sed 's/OS=//')
    [[ $(expr index "${OPERATING_SYSTEM}" "Win") -eq 1 ]] && ON_WINDOWS=1
}

### Get working directory
get_mvn_dist_path() {
    path="$( pwd )"

    if [[ ${ON_WINDOWS} -eq 1 ]]; then
        bs="${BASH_SOURCE[0]}"
        dn="$( dirname '${bs}' )"
        cd "${dn}"
        WD="$( pwd )"
        mvn_dist_home="${WD}"
    else
        WD="$( cd $( dirname $( readlink -f ${BASH_SOURCE[0]} ) ) && pwd )"
    fi
}

# Source dependencies
source_dependencies() {

    applications_cfg="${mvn_dist_home}/${applications_cfg}"
    settings_cfg="${mvn_dist_home}/${settings_cfg}"

    . "${WD}/functions.sh"
    eval $( cat "${settings_cfg}" )
}

get_mvn_binary() {
    MVN_BINARY=$( which "${MVN_BINARY}" ) || ( printf "%s\\n" "Maven binary not found..." && exit 1 )
}

source_strings() {
    . "${WD}/strings.sh"
}

# Copy cfg to ${mvn_dist_home}
copy_cfg() {
    config_array=( "${@}" )

    for i in "${!config_array[@]}"; do
        printf "Copying ${WD}/${config_array[${i}]} to ${mvn_dist_home}\\n"
        cp "${WD}/${config_array[${i}]}" "${mvn_dist_home}"
    done
}

### Check if *.cfg is available in $HOME, copy if not
find_or_copy_cfg() {
    if [[ -d "${mvn_dist_home}" ]]; then
        copy_config_array=()
        if [[ ! -e "${mvn_dist_home}/${applications_cfg}" ]]; then
            copy_config_array+=( "${applications_cfg}" )
        fi
        if [[ ! -e "${mvn_dist_home}/${settings_cfg}" ]]; then
            copy_config_array+=( "${settings_cfg}" )
        fi
    else
        mkdir "${mvn_dist_home}"
        copy_config_array=( "${applications_cfg}" "${settings_cfg}" )
    fi

    if [[ "${#copy_config_array[@]}" -gt 0 ]]; then
        copy_cfg "${copy_config_array[@]}"
    fi
}

### Utility for formatting output
calc_terminal_size() {
    terminal_width=$(tput cols)
    terminal_width=$( [[ "${terminal_width}" -le "${MAX_TERMINAL_WIDTH}" ]] && printf "%s" "${terminal_width}" || printf "%s" "${MAX_TERMINAL_WIDTH}" )

    if [[ "${terminal_width}" -lt "${MIN_TERMINAL_WIDTH}" ]]; then
        printf "The terminal needs a width of at least %s to give feedback in a meaningful format." "${MIN_TERMINAL_WIDTH}" # TODO: Error message?
        exit 1
    fi
}


calc_flag_length() {
    flag_length=0

    for i in "${!options[@]}"; do
        if [[ ${#i} -gt ${flag_length} ]]; then
            flag_length=${#i}
        fi
    done

    flag_length+=2
}

### Options
display_options() {
    options=(
                ["-p, --path=/path/to/source"]="Path to the folder holding the applications to build."
                ["-a, --applications"]="Comma separated list of applications to build."
                ["-f, --force"]="Force mvn-dist to build applications provided by -a|--applications in given order. This also supports custom names of folders holding the applications."
                ["-s, --skip-tests"]="Do not run integration tests."
                ["-c, --continue-on-error"]="Continue building the next application on build failure."
                ["-l, --split-logs"]="Split log for each application. Makes sense when utilizing -c|--continue-on-error."
                ["-v, --verbose"]="Print full Maven output."
                ["-h, --help"]="This help page."
                ["-e, --examples"]="Show usage examples."
                ["-n, --do-not-disturb"]="Do not disturb when build is finished."
    )

    calc_flag_length

    for i in "${!options[@]}"; do
        printf "%-${flag_length}s" "${i}"
        width=$(( terminal_width - flag_length ))
        while read -r -d " " word || [[ -n "${word}" ]]; do
            if [[ $(( ${#word} + 1 )) -lt ${width} ]]; then
                printf "%s " "${word}"
                width=$(( width - ${#word} - 1 ))
            else
                printf "\\n%-${flag_length}s%s " " " "${word}"
                width=$(( terminal_width - flag_length - ${#word} ))
            fi
        done <<< "${options[${i}]}"
        printf "\\n"
    done
}

strip_comment() {
    printf "%s" "${1}" | sed "s/#.*$//" | xargs
}

### Read applications.cfg, declare as an array
parse_applications_from_config() {
    while read line || [[ -n "${line}" ]]; do
        parsed_line=$(strip_comment "${line}")

        if [[ -n "${parsed_line}" ]]; then
            has_specified_submodules=$(grep ":" <<< "${parsed_line}")

            if [[ -n "${has_specified_submodules}" && "${has_specified_submodules}" != "\\n" ]]; then
                string_remainder="$(echo "${parsed_line}" | sed "s/^.*://")"
                submodules=""

                if [[ $(grep "," <<< "${string_remainder}") ]]; then
                    submodule="${string_remainder:0:$(expr index ${string_remainder} ",")}"
                else
                    submodule="${string_remainder}"
                fi

                while [[ "${submodule}" ]]; do
                    submodules+="${submodule}"
                    string_remainder="${string_remainder#${submodule}}"
                    string_remainder="${string_remainder#,}"

                    if [[ -n $(grep "," <<< "${string_remainder}") ]]; then
                        submodule="${string_remainder:0:$(expr index ${string_remainder} ",")}"
                    else
                        submodule=${string_remainder}
                    fi
                done

                main_module=$(echo "${parsed_line}" | sed "s/:.*$//")
                applications_from_config_array+=( "${main_module}:-pl ${submodules}" )
            else
                applications_from_config_array+=( "${parsed_line}" )
            fi
        fi

    done < "${applications_cfg}"
}

### Generic warning function
print_warning() {
    printf "\\n%b*** %s *** %b\\n\\n" "${RED}" "${1}" "${NO_COLOUR}"
}

### Utility function for padding
pad() {
    length=$1
    i=0
    while [[ "${i}" -lt "${length}" ]]; do
        printf "%s" "*"
        i=$(( i+1 ))
    done
}

### Manual
usage() {
    printf "%b" "${USAGE}"
}

###
mvn_dist_help() {
    printf "%b" "${HELP}"
}

### Parse cli applications.
parse_applications_from_cli() {
    IFS=',' read -r -a applications_from_cli_array <<< "${1}"

    if [[ "${force}" -eq 0 ]];then
        compare_applications

        if [[ "${#application_difference_array[@]}" -gt 0 ]]; then
            print_warning "$(printf "Unknown application %s" "${application_difference_array[*]}")"
            exit 1
        fi

        sort_applications
    else
        if [[ "${#applications_from_cli_array[@]}" -gt 0 ]]; then
            unset "applications_from_config_array"
            applications_from_config_array=( "${applications_from_cli_array[@]}" )
        else
            print_warning "${NO_APPLICATIONS}"
            exit 1
        fi
    fi
}

find_application_difference() {
    local i
    skip=
    for i in "${!applications_from_config_array[@]}"; do
        result=$(expr match "${applications_from_config_array[${i}]}" "${check_diff_application}")
        if [[ ${result} -gt 0 ]]; then
            skip=1
            break
        fi
    done

    [[ -n ${skip} ]] || application_difference+=( "${check_diff_application}" )
}

### Declare difference between expected and actual applications as an array
compare_applications() {
    local i
    application_difference_array=()

    for i in "${!applications_from_cli_array[@]}"; do
        check_diff_application="${applications_from_cli_array[${i}]}"
        find_application_difference
    done

    declare -a application_difference
}


handle_submodules() {
   local i;

   for i in "${!applications_from_cli_array[@]}"; do
        cli_app="${applications_from_cli_array[i]}"
        pl=

        if [[ $(grep ":" <<< "${applications_from_cli_array[i]}") ]]; then
            cli_app=$(echo "${applications_from_cli_array[i]}" | sed "s/:.*//")
            module_string=$(echo "${applications_from_cli_array[i]}" | sed "s/.*://")
            pl=1
        fi

        if [[ $(grep "${cli_app})" <<< "${config_app}") || $(grep "${config_app}" <<< "${cli_app}") ]]; then
            if [[ -n "${pl}" ]]; then
                order+=( "${cli_app}:-pl ${module_string}" )
            else
                order+=( "${applications_from_cli_array[$i]}" )
            fi
            break
        fi

    done
}


### Sort applications. Uses the applications.cfg order.
sort_applications() {
    local i;

    for i in "${!applications_from_config_array[@]}"; do
        config_app="${applications_from_config_array[i]}"

        if [[ $(grep ":" <<< "${applications_from_config_array[i]}") ]]; then
            config_app=$(echo "${applications_from_config_array[i]}" | sed "s/:.*//")
        fi

        handle_submodules

    done

    unset "applications_from_config_array"
    applications_from_config_array=( "${order[@]}" )
}

### Strings for displaying time spent.
calc_time_spent() {
    TIME_SPENT=$(( SECONDS - START_TIME))
    MINUTES_SPENT=$(( TIME_SPENT / 60 ))
    SECONDS_SPENT=$(( TIME_SPENT % 60 ))

    if [[ ${SECONDS_SPENT} -eq 1 ]]; then
        SECOND_STRING="1 second"
    elif [[ ${SECONDS_SPENT} -gt 1 ]];then
        SECOND_STRING="${SECONDS_SPENT} seconds"
    fi

    if [[ ${MINUTES_SPENT} -eq 1 ]]; then
        MINUTE_STRING="1 minute"
    elif [[ ${MINUTES_SPENT} -gt 1 ]];then
        MINUTE_STRING="${MINUTES_SPENT} minutes"
    fi

    [[ -n ${SECOND_STRING} && -n ${MINUTE_STRING} ]] && MINUTE_STRING="${MINUTE_STRING} and "
}

### Parse options, assign values to variables.
parse_options_and_initialize_values() {
    available_options_string=$(getopt -o "desa:vzchfblnp:P:" -l "examples,skip-tests,fix-bugs,debug,do-not-disturb,split-logs,verbose,continue-on-error,force,path:,profile:,applications:,help" -- "$@")
    eval set -- "${available_options_string}"

    debug 13 "$@"

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -a|--applications) chosen_applications="${2}" ; shift 2 ;;
            -P|--profile) build_profile="${2}" ; shift 2 ;;
            -f|--force) force=1 ; shift ;;
            -n|--do-not-disturb) skip_notification=1 ; shift ;;
            -s|--skip-tests) skip_tests="-DskipTests" ; shift ;;
            -p|--path) path="${2}" ; shift 2 ;;
            -l|--split-logs) split_log=1 ; shift ;;
            -c|--continue-on-error) continue=1 ; shift ;;
            -b|--fix-bugs) printf "%b" "${FIX}" && exit 0 ;;
            -v|--verbose) verbose=1 ; shift ;;
            -h|--help) mvn_dist_help && exit 0 ;;
            -e|--examples) usage && exit 0 ;;
            -d|--debug) DEBUG=1 ; shift ;;
            --) shift ; break ;;
            *) printf "%s" "$0: Error... Unknown flag. $1" 1>&2; exit 1 ;;
        esac
    done
}

### Save cursor position at the beginning of the line
initialize_cursor_position() {
    printf "\\n"
    save_cursor_position
}

### Check if we have received applications from cli.
application_parsed_from_cli() {
    ### Parse applications from cli if necessary
    [[ -n "${chosen_applications}" ]] && parse_applications_from_cli "${chosen_applications}"
}

### Check for existence of application directory. Magic slash functionality.
application_folder_exists() {
    cd "${path}" || (print_warning "${INVALID_PATH}" && exit 1)
    absolute_path="$(pwd)"
}

prepare_build() {
    [[ ${build_profile} == "-Pit" && "${skip_tests}" != "-DskipTests" ]] && test_string=" with integration tests " || test_string="" # TODD: Remove the test string

    if [[ -n $(grep ":" <<< "${applications_from_config_array[${i}]}") ]]; then
        application=$(echo "${applications_from_config_array[${i}]}" | sed "s/:.*//")
        specified_modules=$(echo "${applications_from_config_array[${i}]}" | sed "s/.*://g")
    else
        application="${applications_from_config_array[${i}]}"
    fi

    build_parameters=""

    [[ -n "${build_profile}" ]] && build_parameters+="${build_profile} "
    [[ -n "${specified_modules}" ]] && build_parameters+="${specified_modules} "
    [[ -n "${skip_tests}" ]] && build_parameters+="${skip_tests}"

    application_path="${absolute_path}/${application}"

    build_text=$(printf "* Build %s" "${test_string}")
    truncate_application_name

    if [[ "${split_log}" -eq 1 ]]; then
        log="/tmp/${application}-build.log"
    fi

}

build_with_spinner() {
    printf "* Build %b%s%b%s" "${GREEN}" "${pretty_print}" "${NO_COLOUR}" "${test_string}"
    if [[ -n "${build_parameters}" ]]; then
        "${MVN_BINARY}" clean install ${build_parameters} &>"${log}" & pid=$!
    else
        "${MVN_BINARY}" clean install &>"${log}" & pid=$!
    fi
    spin_cursor
}

build_verbose() {
    if [[ -n "${build_parameters}" ]]; then
        "${MVN_BINARY}" clean install ${build_parameters} & pid=$!
    else
        "${MVN_BINARY}" clean install & pid=$!
    fi
    if ! wait "${pid}"; then
        if [[ "${continue}" -ne 1 ]]; then
            print_warning "${BUILD_FAILURE}" && exit 1
        else
            error_list["${error_count}"]="\\n\\nApplication:\\t${application}\nLog:\\t\\t${BOLD}${BLUE}${log}${NO_COLOUR}"
            error_count=$(( error_count+1 ))
        fi
    fi
}

### Build applications.
build_applications() {
    for i in "${!applications_from_config_array[@]}"; do
        prepare_build
        ### Check if application directory exists
        if [[ -d  "${application_path}" ]]; then

            ### If we cannot enter the folder at this stage, permissions are the usual suspects.
            cd "${application_path}" || (print_warning "${PERMISSIONS}" && exit 1)

            ### Spinner or full maven output
            if [[ "${verbose}" -eq 0 ]]; then
                build_with_spinner
            else
                build_verbose
            fi

            build_count=$(( build_count + 1 ))
        else
            printf "* Build failure: %s" "${application}"
            print_warning "${NOT_FOUND}"
        fi

        unset specified_modules
        unset build_parameters
    done
}

### Utility function for formatting output.
truncate_application_name() {
    max_length=$(( terminal_width - $(( ${#build_text} + 6 )) ))

    if [[ ${max_length} -lt 3 ]]; then
        printf "The terminal is too narrow to give meaningful output. Please resize to a width of minimum %s.\\n", "${MIN_TERMINAL_WIDTH}"
        exit 1
    elif [[ ${max_length} -gt ${#application} ]]; then
        pretty_print="${application}"
    else
        pretty_print="${application:0:$max_length}..."
    fi
}

check_for_failure() {
    if ! wait "${pid}"; then
        move_cursor_backward 2
        delete_until_eol
        printf "%b%s%b" "${RED}${BLINK}${BOLD}" "!!" "${NO_COLOUR}\\n"

        if [[ "${continue}" -ne 1 ]]; then
            printf "\\n\\n"
            tail -n "${LOG_TAIL_LENGTH}" "${log}"
            print_warning "${BUILD_FAILURE}" && exit 1
        else
            error_list[$error_count]="\\n\\nApplikasjon:\\t${application}\nLogg:\\t\\t${BOLD}${BLUE}${log}${NO_COLOUR}"
            error_count=$(( error_count+1 ))
        fi

    else
        move_cursor_backward 2
        delete_until_eol
        printf "%b%s%b" "${GREEN}${BOLD}" "OK" "${NO_COLOUR}\\n"
    fi
}

### Spin functionality
spin_cursor() {
    spin="-\|/"
    i=0

    move_cursor_forward $(( terminal_width - $(( ${#pretty_print} + ${#test_string} + miscellaneous_text_length )) ))
    printf "%b" "${GREEN}"
    printf "%s" "${spin:$i:1}"

    ### Check if still building, spin
    while kill -0 "${pid}" 2>/dev/null
    do
        i=$(( (i+1) %4 ))
        move_cursor_backward 1
	    printf "%s" "${spin:${i}:1}"
        sleep .1
    done

    printf "%b" "${NO_COLOUR}"

    ### check if build failed
    check_for_failure
}

### Generates error message(s)
generate_error_message() {
    if [[ ${error_count} -gt 0 ]]; then
        printf "\\n\\n"
        error="Build failure"
        pad_length=$(( (terminal_width / 2) -  (${#error} / 2) - 1 ))
        pad "${pad_length}"
        printf " %b " "${RED}${BOLD}${error}${NO_COLOUR}"
        pad "${pad_length}"
        for i in "${!error_list[@]}"; do
            printf "%b" "${error_list[$i]}"
        done
        printf "\\n\\n"
        pad "${terminal_width}"
        printf "\\n"
        ERROR_MSG=" with ${RED}${BOLD}${error_count} errors${NO_COLOUR}..."
    fi
}

### Calculate and print start time
print_time() {
  date +"%T"
}

### Summarize
display_summary() {
    if [[ "${build_count}" -gt 0 ]]; then
        command -v notify-send > /dev/null 2>&1 && ([[ ${skip_notification} -eq 0 ]] && notify-send -u normal -t 10000 -i terminal "Build completed" "Build took \\n<i>${MINUTE_STRING}${SECOND_STRING}</i>")
        command -v osascript > /dev/null 2>&1 && ([[ ${skip_notification} -eq 0 ]] && osascript -e "display notification \"Build took ${MINUTE_STRING}${SECOND_STRING}\" with title \"Build completed\"")
        printf "%b%b%s%b%b" "\n\n" "${GREEN}${BOLD}" "Build completed" "${NO_COLOUR}" " in ${MINUTE_STRING}${SECOND_STRING}${ERROR_MSG}\\n\\n"
    else
        command -v notify-send > /dev/null 2>&1 && [[ ${skip_notification} -eq 0 ]] && notify-send -u normal -t 10000 -i terminal "Done" "Found zero applications to build"
        command -v osascript > /dev/null 2>&1 && ([[ ${skip_notification} -eq 0 ]] && osascript -e "display notification \"Found zero applications to build...\" with title \"Build completed\"")
        printf "Build finished. Did not find any applications to build.\\n\\n"
    fi
}

#### Start script
check_for_windows
get_mvn_dist_path
[[ ${ON_WINDOWS} -eq 0 ]] && find_or_copy_cfg
source_dependencies
calc_terminal_size
source_strings
parse_options_and_initialize_values "$@"
[[ ${ON_WINDOWS} -eq 0 ]] && get_mvn_binary && [[ $? == 1 ]] && exit 1
parse_applications_from_config
initialize_cursor_position
application_parsed_from_cli
application_folder_exists
build_applications
generate_error_message
calc_time_spent
display_summary
### End script
