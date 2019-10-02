#!/usr/bin/env bash

## TODO: sanity check for profiles - How the hell do we do that?

DEBUG=0
### Arrays
declare -A options
declare -a error_list=()
declare -a order=()
declare -a applications_from_cli_array=()
declare -a applications_from_config_array=()
declare -a application_difference_array=()
declare -a profiles=()
### Strings
declare ERROR_MSG=""
declare MVN_DIST_LOG=""
declare build_profile=""
declare log="/tmp/mvn-dist.log"
declare error_log="/tmp/mvn-dist-error.log"
declare chosen_applications=
declare path=.
declare application_path=""
declare absolute_path=""
declare application=""
declare profiles_cfg="profiles.cfg"
declare applications_cfg="applications.cfg"
declare settings_cfg="settings.cfg"
declare mvn_dist_home="${HOME}/.mvn-dist"
declare pretty_print=""
declare available_options_string=""
declare specified_modules=""
### Integers
declare -i START_TIME=$SECONDS
declare -i LOG_TAIL_LENGTH
declare -i MAX_TERMINAL_WIDTH
declare -i MIN_TERMINAL_WIDTH
declare -i terminal_width=80
declare -i flag_length=25
declare -i miscellaneous_text_length=8
declare -i error_count=0
declare -i build_count=0
declare -i pid
### Boolean Simulator
declare -i verbose=0
declare -i force=0
declare -i continue=0
declare -i split_log=0
declare -i skip_notification=0

# Debug
debug() {
    if [[ "${DEBUG}" -eq 1 ]]; then
        array=( "$@" )
        for i in "${!array[@]}"; do
            printf "%s\\n" "${array[${i}]}"
        done
    fi
}

### Get working directory
get_mvn_dist_home() {
    path=$(pwd)
    WD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
}

### Check if applications.cfg is available in $HOME
look_for_cfg() {
    if [[ -d "${mvn_dist_home}" ]]; then
        if [[ ! -e "${mvn_dist_home}/${applications_cfg}" ]]; then
            cp "${WD}/${applications_cfg}" "${mvn_dist_home}"
        fi
        if [[ ! -e "${mvn_dist_home}/${settings_cfg}" ]]; then
            cp "${WD}/${settings_cfg}" "${mvn_dist_home}"
        fi
        if [[ ! -e "${mvn_dist_home}/${profiles_cfg}" ]]; then
            cp "${WD}/${profiles_cfg}" "${mvn_dist_home}"
        fi
    else
        mkdir "${mvn_dist_home}"
        cp "${WD}/${applications_cfg}" "${WD}/${profiles_cfg}" "${WD}/${settings_cfg}" "${mvn_dist_home}"
    fi

    applications_cfg="${mvn_dist_home}/${applications_cfg}"
    settings_cfg="${mvn_dist_home}/${settings_cfg}"
    profiles_cfg="${mvn_dist_home}/${profiles_cfg}"
}

read_settings_cfg() {
  while IFS="=" read -r key value || [[ -n "${key}" ]]; do
        debug "${key}=${value}"
        export "${key}=${value}"
  done < "${settings_cfg}"
}

read_profiles_cfg() {
    while read profile || [[ -n "${profile}" ]]; do
        profiles+=( "${profile}" )
    done < "${profiles_cfg}"
}


### Utility for formatting output
calc_terminal_size() {
    terminal_width=$(tput cols)
    terminal_width=$( ([[ "${terminal_width}" -le "${MAX_TERMINAL_WIDTH}" ]] && printf "%s" "${terminal_width}") || printf "%s" "${MAX_TERMINAL_WIDTH}")
    if [[ "${terminal_width}" -lt "${MIN_TERMINAL_WIDTH}" ]]; then
        printf "The terminal needs a width of at least %s to give feedback in a meaningful format." "${MIN_TERMINAL_WIDTH}"
        exit 1;
    fi
}

### Options
display_options() {
    options=(
                ["-P, --profile"]="One of the profiles provided in profiles.cfg"
                ["-p, --path=/path/to/source"]="Path to the folder holding the applications to build."
                ["-a, --applications"]="Comma separated list of applications to build."
                ["-f, --force"]="Force mvn-dist to build applications provided by -a|--applications in given order. This also supports custom names of folders holding the applications."
                ["-s, --skip-tests"]="Do not run integration tests."
                ["-c, --continue-on-error"]="Continue building the next application on build failure."
                ["-l, --split-logs"]="Split log for each application. Makes sense when utilizing -c|--continue-on-error."
                ["-v, --verbose"]="Print full Maven output"
                ["-h, --help"]="This help page."
                ["-n, --do-not-disturb"]="Do not disturb when build is finished."
    )

    debug "terminal_width:" "${terminal_width}" "${MAX_TERMINAL_WIDTH}" "42"

    flag_length=25 # TODO: Maybe calculate tihs?

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
        printf "\\n\\n"
    done
}


### Strings
NO_COLOUR="\e[0m"
RED="\e[0;031m"
GREEN="\e[0;32m"
BLUE="\e[96m"
BOLD="\e[1m"
BLINK="\e[5m"

UNKNOWN_PROFILE="Unknown maven profile. Please refer to profiles.cfg for valid options."
BUILD_FAILURE="Build failure. Please check the logs for further details."
PERMISSIONS="Unable to access specified directory. Please check the permisions."
NOT_FOUND="Could not find specified application folder."
INVALID_PATH="Could not find specified directory. Please validate specified options."
NO_APPLICATIONS="Could not find any applications to process. Skip -f|--force to build default applications from applications.cfg."

### Tekststreng for bruk av scriptet - typisk usage()
#read_usage() {
read -r -d '' USAGE << EOM

Bygger AKR-applikasjoner i angitt filsti eller nåværende mappe. Logger til\\n/tmp/akr-bygg.log eller /tmp/<akr-applikasjon>-bygg.log og /tmp/akr-bygg-error.log

${GREEN}Usage:${NO_COLOUR}
mvn-dist [options]

${GREEN}Options:${NO_COLOUR}
help=${display_options} && echo ${help}

${GREEN}Examples:${NO_COLOUR}
Build all applications in /mnt/data/git
${BLUE}mvn-dist -p /mnt/data/git${NO_COLOUR}

Build only application named model without integration tests.
${BLUE}mvn-dist --skip-tests -a model${NO_COLOUR}

Build applications model, common and case, force to build in given order.
${BLUE}mvn-dist -a model,common,case -f${NO_COLOUR}

Build an application with a custom name.
${BLUE}mvn-dist -a akr-omniapplikasjon -f${NO_COLOUR}

Build all applications in /mnt/data/git with profile it,\\nContinue building the next application on build error and log separately.
${BLUE}mvn-dist -p /mnt/data/git -P it -c -l${NO_COLOUR}

${GREEN}Tip:${NO_COLOUR}
Use short flags when you need tab completion.
If utilizing --continue-on-error you should consider splitting logs using --split-logs.
Add applications to build in applications.cfg
Add build profiles in profiles.cfg

${GREEN}Known issues:${NO_COLOUR}
applications.cfg and its siblings should be edited using a UNIX flavour due to MS' new-line challenges.
Consider using a terminal with a minimum width of 80 to get decently formatted output.

${GREEN}Configuration files:${NO_COLOUR}
$HOME/.mvn-dist/applications.cfg
$HOME/.mvn-dist/settings.cfg
$HOME/.mvn-dist/profiles.cfg\\n\\n
EOM

#    return "${BRUK}"
#}

### So shoot me
read -r -d '' FIX << EOA
\\n
           ▄▄▄▄▄▄▄▄▄▄▄▄▄
        ▄▀▀             ▀▀▄
       █                   █
      █                     █
     █   ▄▄▄▄▄▄▄   ▄▄▄▄▄▄▄   █
    █   █████████ █████████   █
    █ ██▀    ▀█████▀    ▀██  █
   ██████   █▀█ ███   █▀█ ██████
   ██████   ▀▀▀ ███   ▀▀▀ ██████
    █  ▀█     ▄██ ██▄    ▄█▀  █
    █    ▀█████▀   ▀█████▀    █
    █               ▄▄▄       █
    █       ▄▄▄▄██▀▀█▀▀█▄     █
    █     ▄██▄█▄▄█▄▄█▄▄██▄    █
    █     ▀▀█████████████▀    █
   ▐▓▓▌                     ▐▓▓▌
   ▐▐▓▓▌▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▐▓▓▌▌
   █══▐▓▄▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▄▓▌══█
  █══▌═▐▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▌═▐══█
  █══█═▐▓▓▓▓▓▓▄▄▄▄▄▄▄▓▓▓▓▓▓▌═█══█
  █══█═▐▓▓▓▓▓▓▐██▀██▌▓▓▓▓▓▓▌═█══█
  █══█═▐▓▓▓▓▓▓▓▀▀▀▀▀▓▓▓▓▓▓▓▌═█══█

  █   █ █  █ █▀▀█ ▀▀█▀▀ ▀█ █ ▀█
  █▄█▄█ █▀▀█ █▄▄█   █   █▀ ▀ █▀
   ▀ ▀  ▀  ▀ ▀  ▀   ▀   ▄  ▄ ▄\\n\\n\\n

EOA

### Read applications.cfg, declare as an array
parse_applications_from_config() {
    while read line || [[ -n "${line}" ]]; do
        parsed_line=$(printf "%s" "${line}" | sed "s/#.*$//" | xargs)
        if [[ -n "${parsed_line}" ]]; then
            has_specified_modules=$(echo "${parsed_line}" | grep ":")

            if [[ -n "${has_specified_modules}" && "${has_specified_modules}" != "\n" ]]; then
                string_remainder="$(echo "${parsed_line}" | sed "s/^.*://")"
                modules=""
                debug "String Remainder: ${string_remainder}"
                module="${string_remainder:0:$(expr index ${string_remainder} ",")}"

                while [[ "${module}" ]]; do
                    modules+="${module}"
                    debug "modules: ${modules}"
                    string_remainder="${string_remainder#${module}}"
                    string_remainder="${string_remainder#,}"
                    if [[ -n $(echo "${string_remainder}" | grep ",") ]]; then
                        module="${string_remainder:0:$(expr index ${string_remainder} ",")}"
                    else
                        module=${string_remainder}
                    fi
                done
                debug "Modules: ${modules}"
                main_module=$(echo "${parsed_line}" | sed "s/:.*$//")
                applications_from_config_array+=( "${main_module}:-pl ${modules}" )
            else
                applications_from_config_array+=( "${parsed_line}" )
            fi
        fi

    done < "${applications_cfg}"
    debug "${applications_from_config_array[@]}"
}

### Layout functions
move_cursor_up() {
    printf "\\033[%qA" "${1}"
}

move_cursor_down() {
    printf "\\033[%qB" "${1}"
}

move_cursor_forward() {
    printf "\\033[%qC" "${1}"
}

move_cursor_backward() {
    printf "\\033[%qD" "${1}"
}

save_cursor_position() {
    printf "\\033[s"
}

recall_cursor_position() {
    printf "\\033[u"
}

delete_until_end_of_line() {
    printf "\\033[0K"
}
### /Layout functions

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
    display_options
    printf "%b" "${USAGE}"
}

### Parse cli applications.
parse_applications_from_cli() {
    IFS=',' read -r -a applications_from_cli_array <<< "${1}"

    if [[ "${force}" -eq 0 ]];then
        expected_applications

        if [[ "${#application_difference_array[@]}" -gt 0 ]]; then
            print_warning "$(printf "Ukjent applikasjon %s" "${application_difference_array[*]}")"
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


### Declare difference between expected and actual applications as an array
expected_applications() {
    application_difference_array=()
    debug 131313

    for i in "${!applications_from_cli_array[@]}"; do
        skip=
        debug "i=${i}"
        for j in "${!applications_from_config_array[@]}"; do
            result=$(expr match "${applications_from_config_array[${j}]}" "${applications_from_cli_array[${i}]}")
            debug "result: ${result}"
            if [[ ${result} -gt 0 ]]; then
                skip=1
                break
            fi
        done

        [[ -n ${skip} ]] || application_difference+=( "${applications_from_cli_array[$i]}" )

    done

    declare -a application_difference
}

### Sort applications. Uses the applications.cfg order.
sort_applications() {
    for i in "${!applications_from_config_array[@]}"; do
        config_app="${applications_from_config_array[i]}"

        if [[ $(echo "${applications_from_config_array[i]}" | grep ":") ]]; then
            config_app=$(echo "${applications_from_config_array[i]}" | sed "s/:.*//")
        fi

        for j in "${!applications_from_cli_array[@]}"; do
            cli_app="${applications_from_cli_array[j]}"
            pl=

            if [[ $(echo "${applications_from_cli_array[j]}" | grep ":") ]]; then
                debug 35
                cli_app=$(echo "${applications_from_cli_array[j]}" | sed "s/:.*//")
                module_string=$(echo "${applications_from_cli_array[j]}" | sed "s/.*://")
                pl=1
            fi

            debug "cli=${cli_app}, conf=${config_app}"

            if [[ $(echo "${cli_app})" | grep "${config_app}") || $(echo "${config_app}" | grep "${cli_app}") ]]; then
                debug 43
                if [[ -n "${pl}" ]]; then
                    debug "mod_str: ${module_string}"
                    order+=( "${cli_app}:-pl ${module_string}" )
                else
                    order+=( "${applications_from_cli_array[$j]}" )
                fi
                break
            fi

        done
    done

    debug "order: ${order[@]}"
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

    [[ -n ${SECOND_STRING} && -n ${MINUTE_STRING} ]] && MINUTE_STRING="${MINUTE_STRING} og "
}

### Parse options, assign values to variables.
parse_options_and_initalize_values() {
    available_options_string=$(getopt -o "sa:vzchfblnp:P:" -l "skip-tests,fix-bugs,do-not-disturb,split-logs,verbose,continue-on-error,force,path:,profile:,applications:,help" -- "$@")
    eval set -- "${available_options_string}"

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -a|--applications) chosen_applications="${2}" ; shift 2 ;;
            -P|--profile) build_profile="-P${2}" ; shift 2 ;;
            -f|--force) force=1 ; shift ;;
            -n|--do-not-disturb) skip_notification=1 ; shift ;;
            -s|--skip-tests) skip_tests="-DskipTests" ; shift ;;
            -p|--path) path="${2}" ; shift 2 ;;
            -l|--split-logs) split_log=1 ; shift ;;
            -c|--continue-on-error) continue=1 ; shift ;;
            -b|--fix-bugs) printf "%b" "${FIX}" && exit 0 ;;
            -v|--verbose) verbose=1 ; shift ;;
            -h|--help) usage && exit 0 ;;
            --) shift ; break ;;
            *) printf "%s" "$0: Error... Unknown flag. $1" 1>&2; exit 1 ;;
        esac
    done
}

### Save cursor position at the beginning of the line
initalize_cursor_position() {
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

### Build applications.
build_applications() {
    debug "Bygger ${applications_from_config_array[@]}"

    for i in "${!applications_from_config_array[@]}"; do
        [[ ${build_profile} == "-Pit" && "${skip_tests}" != "-DskipTests" ]] && test_string=" with integration tests " || test_string="" # TODD: Remove the test string

        if [[ -n $(echo "${applications_from_config_array[${i}]}" | grep ":") ]]; then
            application=$(echo "${applications_from_config_array[${i}]}" | sed "s/:.*//")
            specified_modules=$(echo "${applications_from_config_array[${i}]}" | sed "s/.*://g")
        else
            application="${applications_from_config_array[${i}]}"
        fi

        build_parameters=""

        [[ -n "${build_profile}" ]] && build_parameters+="${build_profile} "
        debug 11 "${build_parameters}"
        [[ -n "${specified_modules}" ]] && build_parameters+="${specified_modules} "
        debug 12 "${build_parameters}"
        [[ -n "${skip_tests}" ]] && build_parameters+="${skip_tests}"
        debug 13 "${build_parameters}"

        application_path="${absolute_path}/${application}"

        build_text=$(printf "* Build %s" "${test_string}")
        truncate_application_name

        if [[ "${split_log}" -eq 1 ]]; then
            log="/tmp/${application}-build.log"
        fi

        debug "${application_path}"
        ### Check if application directory exists
        if [[ -d  "${application_path}" ]]; then

            ### If we cannot enter the folder at this stage, permissions are the usual suspects.
            cd "${application_path}" || (print_warning "${PERMISSIONS}" && exit 1)

            ### Spinner or full maven output
            if [[ "${verbose}" -eq 0 ]]; then
                printf "* Build %b%s%b%s" "${GREEN}" "${pretty_print}" "${NO_COLOUR}" "${test_string}"
                if [[ -n "${build_parameters}" ]]; then
                    mvn clean install ${build_parameters} 2> >(tee "${error_log}" >&2) &>"${log}" & pid=$!
                else
                    mvn clean install 2> >(tee "${error_log}" >&2) &>"${log}" & pid=$!
                fi
                spin_cursor
            else
                debug 42 "${build_parameters}"
                if [[ -n "${build_parameters}" ]]; then
                    mvn clean install ${build_parameters} > >(tee "${log}" 2> >(tee "${error_log}" >&2)) & pid=$!
                else
                    mvn clean install > >(tee "${log}" 2> >(tee "${error_log}" >&2)) & pid=$!
                    mvn clean install > >(tee "${log}" 2> >(tee "${error_log}" >&2)) & pid=$!
                fi
                if ! wait "${pid}"; then
                    if [[ "${continue}" -ne 1 ]]; then
                        print_warning "${BUILD_FAILURE}" && exit 1
                    else
                        error_list["${error_count}"]="\\n\\nApplication:\\t${application}\nLog:\\t\\t${BOLD}${BLUE}${log}${NO_COLOUR}"
                        error_count=$(( error_count+1 ))
                    fi
                fi
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

### Utility function for displaying output.
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
    if ! wait "${pid}"; then
        move_cursor_backward 2
        delete_until_end_of_line
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
        delete_until_end_of_line
        printf "%b%s%b" "${GREEN}${BOLD}" "OK" "${NO_COLOUR}\\n"
    fi
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

### Summarize
display_summary() {
    if [[ "${build_count}" -gt 0 ]]; then
        command -v notify-send > /dev/null 2>&1 && ([[ ${skip_notification} -eq 0 ]] && notify-send -u normal -t 10000 -i terminal "Build completed" "Build took \\n<i>${MINUTE_STRING}${SECOND_STRING}</i>")
        command -v osascript > /dev/null 2>&1 && ([[ ${skip_notification} -eq 0 ]] && osascript -e "display notification \"Build took ${MINUTE_STRING}${SECOND_STRING}\" with title \"Build completed\"")
        printf "%b%b%s%b%b" "\n\n" "${GREEN}${BOLD}" "Build completed" "${NO_COLOUR}" " after ${MINUTE_STRING}${SECOND_STRING}${ERROR_MSG}\\n\\n"
    else
        command -v notify-send > /dev/null 2>&1 && [[ ${skip_notification} -eq 0 ]] && notify-send -u normal -t 10000 -i terminal "Done" "Found zero applications to build"
        command -v osascript > /dev/null 2>&1 && ([[ ${skip_notification} -eq 0 ]] && osascript -e "display notification \"Found zero applications to build...\" with title \"Build completed\"")
        printf "Build finished. Did not find any applications to build.\\n\\n"
    fi
}

#### Start script
get_mvn_dist_home
look_for_cfg
read_settings_cfg
calc_terminal_size
read_profiles_cfg
parse_applications_from_config
parse_options_and_initalize_values "$@"
initalize_cursor_position
application_parsed_from_cli
application_folder_exists
build_applications
generate_error_message
calc_time_spent
display_summary
### End script
