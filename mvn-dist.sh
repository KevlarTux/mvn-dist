#!/usr/bin/env bash

## TODO: skipModules --> bris-frontend:!bris-frontend-frontend # Exclude
## TODO: skipModules --> bris-frontend:bris-frontend-domain # Include only

DEBUG=0
### Arrays
declare -A options
declare -a error_list=()
declare -a order=()
declare -a applications_from_cli_array=()
declare -a applications_from_config_array=()
declare -a application_difference_array=()
### Strings
declare ERROR_MSG=""
declare build_profile=""
declare log="/tmp/mvn-dist.log"
declare chosen_applications=
declare path=.
declare application_path=""
declare application=""
declare applications_cfg="applications.cfg"
declare settings_cfg="settings.cfg"
declare mvn_dist_home="${HOME}/.mvn-dist"
### Integers
declare -i START_TIME=$SECONDS
declare -i terminal_width
declare -i flag_length=25
declare -i miscellaneous_text_length=8
declare -i error_count=0
declare -i build_count=0
### Boolean Simulator
declare -i verbose=0
declare -i force=0
declare -i continue=0
declare -i split_log=0
declare -i skip_notification=0

MVN_DIST_LOG=""
MAX_TERMINAL_WIDTH=
MIN_TERMINAL_WIDTH=

# Debug
debug() {
    if [[ "${DEBUG}" -eq 1 ]]; then
        array=( "$@" )
        for i in "${!array[@]}"; do
            printf "${array[${i}]}\\n"
        done
    fi
}

### Options
display_options() {
    options=(
                ["-P, --profile"]="Alternativer: it, jrebel"
                ["-p, --path=/sti/til/akr"]="Filsti til mappen som inneholder akr-applikasjonene"
                ["-a, --applikasjoner"]="Navn på applikasjoner som skal bygges, kommaseparert"
                ["-f, --force"]="Tving scriptet til å forsøke å bygge applikasjoner angitt med -a|--applikasjoner i valgt rekkefølge. Dette støtter også custom-navn på mappene"
                ["-s, --skip-tests"]="Ikke kjør tester"
                ["-c, --continue-on-error"]="Fortsett bygg av neste applikasjon ved kompileringsfeil"
                ["-l, --split-logs"]="Splitt bygglogg. Én log per applikasjon. Hendig ved bruk av -c|--continue-on-error dersom en kompileringsfeil oppstår"
                ["-v, --verbose"]="Full maven output"
                ["-h, --help"]="Denne hjelpesiden"
                ["-n, --do-not-disturb"]="Ikke gi forstyrr når bygget er ferdig"
    )

    flag_length=25
    for i in "${!options[@]}"; do
        printf "%-${flag_length}s" "${i}"
        width=$(( terminal_width - flag_length ))
        while read -r -d " " ord || [[ -n "${ord}" ]]; do
            if [[ $(( ${#ord} + 1 )) -lt ${width} ]]; then
                printf "%s " "${ord}"
                width=$(( width - ${#ord} - 1 ))
            else
                printf "\\n%-${flag_length}s%s " " " "${ord}"
                width=$(( terminal_width - flag_length - ${#ord} ))
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
read -r -d '' BRUK << EOM

Bygger AKR-applikasjoner i angitt filsti eller nåværende mappe. Logger til\\n/tmp/akr-bygg.log eller /tmp/<akr-applikasjon>-bygg.log og /tmp/akr-bygg-error.log

${GREEN}Usage:${NO_COLOUR}
bob build-akr [options]

${GREEN}Options:${NO_COLOUR}
$(display_options)

${GREEN}Eksempler:${NO_COLOUR}
Bygg alle akr-applikasjoner under /mnt/data/git/
${BLUE}bob build-akr -p /mnt/data/git${NO_COLOUR}

Bygg alle akr-applikasjoner i nåværende mappe med integrasjonstester
${BLUE}bob build-akr -P it${NO_COLOUR}

Bygg kun akr-modell uten tester
${BLUE}bob build-akr --skip-tests -a akr-modell${NO_COLOUR}

Bygg akr-modell,akr-common og akr-sak i valgt rekkefølge
${BLUE}bob build-akr -a akr-modell,akr-common,akr-sak -f${NO_COLOUR}

Bygg en applikasjon med custom-navn
${BLUE}bob build-akr -a akr-omniapplikasjon -f${NO_COLOUR}

Bygg  alle applikasjoner under /mnt/data/git med integrasjonstester,\\nfortsett bygg av neste applikasjon ved feil og log til separate filer
${BLUE}bob build-akr -p /mnt/data/git -P it -c -l${NO_COLOUR}

${GREEN}Tips:${NO_COLOUR}
Bruk kortversjonen av flagg ved behov for tab completion\\n
Dersom man benytter --continue-on-error eller -c så anbefales det å splitte byggloggene ved hjelp av --split-logs eller -l\\n
Dersom man savner noen applikasjoner kan de legges til i /home/vagrant/.mvn-dist/applications.cfg

${GREEN}Kjente feil:${NO_COLOUR}
Tekstfilen /home/vagrant/.mvn-dist/applications.cfg MÅ redigeres i Unix grunnet newline-utfordringene\\ntil Microsoft. Rekkefølgen i nevnte fil blir default\\n
Formattering av output fungerer best i terminal som har >= 80 kolonner bredde

${GREEN}Konfigurasjonsfiler:${NO_COLOUR}
/home/vagrant/.mvn-dist/applications.cfg\\n\\n
EOM

### So shoot me - et påskeegg
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


### Get working directory
get_mvn_installation_home() {
    debug 1
    path=$(pwd)
    WD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
}

### Check if applications.cfg is available in $HOME
# TODO: Split if
look_for_cfg() {
debug 2
    if [[ -d "${mvn_dist_home}" ]]; then
        if [[ ! -e "${mvn_dist_home}/${applications_cfg}" && ! -e "${mvn_dist_home}/${settings_cfg}" ]]; then
            cp "${WD}/${applications_cfg}" "${WD}/${settings_cfg}" "${mvn_dist_home}"
        fi
    else
        mkdir "${mvn_dist_home}"
        cp "${WD}/${applications_cfg}" "${WD}/${settings_cfg}" "${mvn_dist_home}"
    fi

    applications_cfg="${mvn_dist_home}/${applications_cfg}"
    settings_cfg="${mvn_dist_home}/${settings_cfg}"
}

### Read applications.cfg, declare as an array
parse_applications_from_config() {
    debug 5
    while read -r linje || [[ -n "${linje}" ]]; do
        lest_linje=$(printf "%s" "${linje}" | sed "s/#.*$//" | xargs)
        if [[ "${lest_linje}" != "" ]]; then
            applications_from_config_array+=( "${lest_linje}" )
        fi
    done < "${applications_cfg}"
    declare -a applications_from_config
}

read_settings_cfg() {
debug 3
  while read -r linje || [[ -n "${linje}" ]]; do
    export "${linje}"
  done < "${settings_cfg}"
}

### Utility for formatting output
calc_terminal_size() {
debug 4
    terminal_width=$(tput cols)
    terminal_width=$([[ "${terminal_width}" -le "${MAX_TERMINAL_WIDTH}" ]] && printf "%s" "${terminal_width}" || printf "%s" "${MAX_TERMINAL_WIDTH}")
    if [[ "${terminal_width}" -lt "${MIN_TERMINAL_WIDTH}" ]]; then
        printf "Terminalen må være minimum %i kolonner bred for å gi feedback i et fornuftig format..." "${MIN_TERMINAL_WIDTH}"
        exit 1;
    fi
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
    lengde=$1
    i=0
    while [[ $i -lt "${lengde}" ]]; do
        printf "%s" "*"
        i=$(( i+1 ))
    done
}

### Manual
usage() {
    printf "%b" "${BRUK}"
}

### Parse cli applications.
parse_applications_from_cli() {
    IFS=',' read -r -a applications_from_cli <<< "${1}"

    if [[ "${force}" -eq 0 ]];then
        expected_applications
        if [[ "${#application_difference_array[@]}" -gt 0 ]]; then
            print_warning "$(printf "Ukjent applikasjon %s" "${application_difference_array[*]}")"
            exit 1
        fi

        sort_applications

    else
        if [[ "${#applications_from_cli[@]}" -gt 0 ]]; then
            unset "applications_from_config"
            applications_from_config_array=( "${applications_from_cli[@]}" )
        else
            print_warning "${NO_APPLICATIONS}"
            exit 1
        fi
    fi
}


### Declare difference between expected and actual applications as an array
expected_applications() {
    application_difference_array=()

    for i in "${!applications_from_cli_array[@]}"; do
        skip=

        for j in "${!applications_from_config_array[@]}"; do
            if [[ "${applications_from_cli_array[${i}]}" == "${applications_from_config_array[${j}]}" ]]; then
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
        for j in "${!applications_from_cli_array[@]}"; do
            if [[ "${applications_from_config_array[${i}]}" == "${applications_from_cli_array[${j}]}" ]]; then
                skip=1
                order+=( "${applications_from_config_array[$i]}" )
                break
            fi
        done
    done

    unset "applications_from_config"
    applications_from_config_array=( "${order[@]}" )
    unset "skal_bygges"
}

### Utility function for displaying output.
truncate_application_name() {
    max_length=$(( terminal_width - $(( ${#build_text} + 6 )) ))

    if [[ ${max_length} -lt 3 ]]; then
        printf "Terminalen er for smal til å gi fornuftig output. Resize til minimum %s kolonner og prøv igjen.\\n", "${MIN_TERMINAL_WIDTH}"
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
    wait "${pid}"

    ### check if build failed
    if [[ $? -ne 0 ]]; then
        move_cursor_backward 2
        delete_until_end_of_line
        printf "%b%s%b" "${RED}${BLINK}${BOLD}" "!!" "${NO_COLOUR}\\n"

        if [[ "${continue}" -ne 1 ]]; then
            printf "\\n\\n"
            tail -n 400 "${log}"
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

### Strings for displaying time spent.
calc_time_spent() {
    debug 12
    TID_BRUKT=$(( SECONDS - START_TIME))
    MINUTTER=$(( TID_BRUKT / 60 ))
    SEKUNDER=$(( TID_BRUKT % 60 ))

    if [[ ${SEKUNDER} -eq 1 ]]; then
        SEKUND_STRENG="1 sekund"
    elif [[ ${SEKUNDER} -gt 1 ]];then
        SEKUND_STRENG="${SEKUNDER} sekunder"
    fi

    if [[ ${MINUTTER} -eq 1 ]]; then
        MINUTT_STRENG="1 minutt"
    elif [[ ${MINUTTER} -gt 1 ]];then
        MINUTT_STRENG="${MINUTTER} minutter"
    fi

    [[ -n ${SEKUND_STRENG} && -n ${MINUTT_STRENG} ]] && MINUTT_STRENG="${MINUTT_STRENG} og "
}

### Parse options, assign values to variables.
parse_options_and_initalize_values() {
    debug 6
    options=$(getopt -o "sa:vzchfblnp:P:" -l "skip-tests,fix-bugs,do-not-disturb,split-logs,verbose,continue-on-error,force,path:,profile:,applikasjoner:,help" -- "$@")
    eval set -- "${options}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--applikasjoner) chosen_applications="${2}" ; shift 2 ;;
            -P|--profile)
                    case "$2" in
                        jrebel) build_profile="-Pjrebel" ; shift 2 ;;
                        it) build_profile="-Pit" ; shift 2 ;;
                        *) print_warning "${UNKNOWN_PROFILE}" && exit 1 ;;
                    esac ;;
            -f|--force) force=1 ; shift ;;
            -n|--do-not-disturb) skip_notification=1 ; shift ;;
            -s|--skip-tests) skip_tester="-DskipTests" ; shift ;;
            -p|--path) path="${2}" ; shift 2 ;;
            -l|--split-logs) split_log=1 ; shift ;;
            -c|--continue-on-error) continue=1 ; shift ;;
            -b|--fix-bugs) printf "%b" "${FIX}" && exit 0 ;;
            -v|--verbose) verbose=1 ; shift ;;
            -h|--help) usage && exit 0 ;;
            --) shift ; break ;;
            *) printf "%s" "$0: feil - ukjent flagg - prøv igjen $1" 1>&2; exit 1 ;;
        esac
    done
}

### Save cursor position at the beginning of the line
initalize_cursor_position() {
    debug 7
    printf "\\n"
    save_cursor_position
}

### Check if we have received applications from cli.
application_parsed_from_cli() {
    debug 8
    ### Parse applications from cli if necessary
    [[ -n "${chosen_applications}" ]] && parse_applications_from_cli "${chosen_applications}"
}

### Check for existence of application directory. Magic slash functionality.
application_folder_exists() {
    debug 9 "${path}"
    cd "${path}" && absolute_path="$(pwd)" || (print_warning "${INVALID_PATH}" && exit 1)
}

### Build applications.
build_applications() {
    for i in "${!applications_from_config_array[@]}"; do
        [[ ${build_profile} == "-Pit" && "${skip_tester}" != "-DskipTests" ]] && test_string=" with integration tests" || test_string=""
        application="${applications_from_config_array[${i}]}"
        application_path="${absolute_path}/${application}"

        build_text=$(printf "* Build %s" "${test_string}")
        debug "${application}" "${application_path}"
        truncate_application_name

        if [[ "${split_log}" -eq 1 ]]; then
            log="/tmp/${application}-build.log"
        fi

        ### Check if application directory exists
        if [[ -d  "${application_path}" ]]; then

            ### If we cannot enter the folder at this stage, permissions are the usual suspects.
            cd "${application_path}" || (print_warning "${PERMISSIONS}" && exit 1)

            ### Spinner or full maven output
            if [[ "${verbose}" -eq 0 ]]; then
                printf "* Build %b%s%b%s" "${GREEN}" "${pretty_print}" "${NO_COLOUR}" "${test_string}"
                mvn clean install ${build_profile} ${skip_tester} 2> >(tee /tmp/mvn-dist-error.log >&2) &>"${log}" & pid=$!
                spin_cursor #"${pid}" "${application}" "${test_string}" "${pretty_print}"
            else
                mvn clean install ${build_profile} ${skip_tester} > >(tee "${log}" 2> >(tee /tmp/mvn-dist-error.log >&2)) & pid=$!
                wait "${pid}"
                if [[ $? -ne 0 ]]; then
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
    done
}

### Generates error message(s)
generate_error_message() {
    debug 11
    if [[ ${error_count} -gt 0 ]]; then
        printf "\\n\\n"
        feil="Build failure"
        padlengde=$(( (terminal_width / 2) -  (${#feil} / 2) - 1 ))
        pad "${padlengde}"
        printf " %b " "${RED}${BOLD}${feil}${NO_COLOUR}"
        pad "${padlengde}"
        for i in "${!error_list[@]}"; do
            printf "%b" "${error_list[$i]}"
        done
        printf "\\n\\n"
        pad "{$terminal_width}"
        printf "\\n"
        ERROR_MSG=" with ${RED}${BOLD}${error_count} errors${NO_COLOUR}..."
    fi
}

### Summarize
display_summary() {
    debug 13
    if [[ "${build_count}" -gt 0 ]]; then
        command -v notify-send > /dev/null 2>&1 && ([[ ${skip_notification} -eq 0 ]] && notify-send -u normal -t 10000 -i terminal "Bygg Ferdig" "Bygget tok\\n<i>${MINUTT_STRENG}${SEKUND_STRENG}</i>")
        command -v osascript > /dev/null 2>&1 && ([[ ${skip_notification} -eq 0 ]] && osascript -e "display notification \"Bygget tok ${MINUTT_STRENG}${SEKUND_STRENG}\" with title \"Bygg Ferdig\"")
        printf "%b%b%s%b%b" "\n\n" "${GREEN}${BOLD}" "Bygg ferdig" "${NO_COLOUR}" " etter ${MINUTT_STRENG}${SEKUND_STRENG}${ERROR_MSG}\\n\\n"
    else
        command -v notify-send > /dev/null 2>&1 && [[ ${skip_notification} -eq 0 ]] && notify-send -u normal -t 10000 -i terminal "Ferdig" "Fant ingenting å  bygge"
        command -v osascript > /dev/null 2>&1 && ([[ ${skip_notification} -eq 0 ]] && osascript -e "display notification \"Fant ingenting å bygge...\" with title \"Bygg Ferdig\"")
        printf "Fant ingenting å gjøre. Ingen applikasjoner ble bygd.\\n\\n"
    fi
}

#### Start script
get_mvn_installation_home
look_for_cfg
read_settings_cfg
calc_terminal_size
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
