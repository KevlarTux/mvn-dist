#!/usr/bin/env bash

### Arrays
declare -A OPTIONS
declare -a feilliste=()
declare -a rekkefolge=()
### Tekststrenger
declare FEILTEKST=""
declare byggprofil=""
declare logg="/tmp/akr-bygg.log"
declare applikasjonerDOTCFG=""
declare applikasjonsvalg=
declare path=.
### Heltall
declare -i STARTTID=$SECONDS
declare -i maks_terminalbredde=120
declare -i min_terminalbredde=60
declare -i terminalbredde=$(tput cols)
declare -i flagglengde=25
declare -i diverse_tekstgrumslengde=8
declare -i feilcount=0
declare -i byggcount=0
### Boolean emulator
declare -i verbose=0
declare -i force=0
declare -i continue=0
declare -i splitt_logg=0
declare -i dropp_notifikasjon=0

### Finn ut hvor scriptet kjøres fra
finn_working_directory() {
    WD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
}

### Sjekk om applikasjoner.cfg er tilgjengelig fra $HOME
se_etter_cfg() {
    if [ -d $HOME/.build-akr ]; then
        if [ ! -e $HOME/.build-akr/applikasjoner.cfg ]; then
            cp "${WD}"/"applikasjoner.cfg" $HOME/.build-akr
        fi
    else
        mkdir $HOME/.build-akr
        cp "${WD}"/"applikasjoner.cfg" $HOME/.build-akr
    fi

    applikasjonerDOTCFG="$HOME/.build-akr/applikasjoner.cfg"
}

### Les applikasjoner.cfg, deklarer som array
parse_applikasjoner_fra_config() {
    applikasjoner_fra_config=()
    while read -r linje || [[ -n "${linje}" ]]; do
        lest_linje=$(printf "${linje}" | sed "s/#.*$//" | xargs)
        if [ "${lest_linje}" != "" ]; then
            applikasjoner_fra_config+=( "${lest_linje}" )
        fi
    done < "${applikasjonerDOTCFG}"
    declare -a applikasjoner_fra_config
}

### Hjelpefunksjon for oppsett av formattering
kalkuler_terminalstorrelse() {
    terminalbredde=$([ ${terminalbredde} -le ${maks_terminalbredde} ] && printf ${terminalbredde} || printf ${maks_terminalbredde})
    if [ ${terminalbredde} -lt ${min_terminalbredde} ]; then
        printf "Terminalen må være minimum %i kolonner bred for å gi feedback i et fornuftig format..." "${min_terminalbredde}"
        exit 1;
    fi
}

### Skriv ut options-delsen av usage()
skriv_ut_options() {
    ### OPTIONS skal autogenereres
    OPTIONS=(
                ["-P, --profile"]="Alternativer: it, jrebel"
                ["-p, --path=/sti/til/akr"]="Filsti til mappen som inneholder akr-applikasjonene"
                ["-a, --applikasjoner"]="Navn på applikasjoner som skal bygges, kommaseparert"
                ["-f, --force"]="Tving scriptet til å forsøke å bygge applikasjoner angitt med -a|--applikasjoner i valgt rekkefølge. Dette støtter også custom-navn på mappene"
                ["-s, --skip-tests"]="Ikke kjør tester"
                ["-c, --continue-on-error"]="Fortsett bygg av neste applikasjon ved kompileringsfeil"
                ["-l, --split-logs"]="Splitt bygglogg. Én logg per applikasjon. Hendig ved bruk av -c|--continue-on-error dersom en kompileringsfeil oppstår"
                ["-v, --verbose"]="Full maven output"
                ["-h, --help"]="Denne hjelpesiden"
                ["-n, --do-not-disturb"]="Ikke gi forstyrr når bygget er ferdig"
    )

    flagglengde=25
    for i in "${!OPTIONS[@]}"; do
        printf "%-${flagglengde}s" "${i}"
        width=$(( $terminalbredde - ${flagglengde} ))
        while read -r -d " " ord || [[ -n "${ord}" ]]; do
            if [[ $(( ${#ord} + 1 )) -lt ${width} ]]; then
                printf "%s " "${ord}"
                width=$(( $width - ${#ord} - 1 ))
            else
                printf "\\n%-${flagglengde}s%s " " " "${ord}"
                width=$(( $terminalbredde - $flagglengde - ${#ord} ))
            fi
        done <<< "${OPTIONS[${i}]}"
        printf "\\n\\n"
    done
}

### Tekststrenger
### Generell tekst til ymse bruk
INGEN_FARGE="\e[0m"
ROD="\e[0;031m"
GRONN="\e[0;32m"
BLAA="\e[96m"
BOLD="\e[1m"
BLINK="\e[5m"

UKJENT_PROFIL="Ukjent maven-profil. Gyldige parametere: it, jrebel og excludeConfigServer."
BYGG_FEILET="Bygg feilet. Se /tmp/akr[-applikasjon]-bygg.log for flere detaljer."
RETTIGHETER="Kunne ikke bytte filsti til gitt applikasjon. Sjekk rettigheter."
IKKE_FUNNET="Applikasjonsmappen ser ikke ut til å eksistere under angitt filsti. "
UGYLDIG_FILSTI="Vennligst angi en gyldig filsti til mappen med AKR. Angitt path ser ikke ut til å eksistere."
INGEN_APPLIKASJONER="Ingen applikasjoner angitt. Dropp -f|--force eller angi hvilke applikasjoner som skal bygges."

### Tekststreng for bruk av scriptet - typisk usage()
read -r -d '' BRUK << EOM

Bygger AKR-applikasjoner i angitt filsti eller nåværende mappe. Logger til\\n/tmp/akr-bygg.log eller /tmp/<akr-applikasjon>-bygg.log og /tmp/akr-bygg-error.log

${GRONN}Usage:${INGEN_FARGE}
bob build-akr [options]

${GRONN}Options:${INGEN_FARGE}
$(skriv_ut_options)

${GRONN}Eksempler:${INGEN_FARGE}
Bygg alle akr-applikasjoner under /mnt/data/git/
${BLAA}bob build-akr -p /mnt/data/git${INGEN_FARGE}

Bygg alle akr-applikasjoner i nåværende mappe med integrasjonstester
${BLAA}bob build-akr -P it${INGEN_FARGE}

Bygg kun akr-modell uten tester
${BLAA}bob build-akr --skip-tests -a akr-modell${INGEN_FARGE}

Bygg akr-modell,akr-common og akr-sak i valgt rekkefølge
${BLAA}bob build-akr -a akr-modell,akr-common,akr-sak -f${INGEN_FARGE}

Bygg en applikasjon med custom-navn
${BLAA}bob build-akr -a akr-omniapplikasjon -f${INGEN_FARGE}

Bygg  alle applikasjoner under /mnt/data/git med integrasjonstester,\\nfortsett bygg av neste applikasjon ved feil og logg til separate filer
${BLAA}bob build-akr -p /mnt/data/git -P it -c -l${INGEN_FARGE}

${GRONN}Tips:${INGEN_FARGE}
Bruk kortversjonen av flagg ved behov for tab completion\\n
Dersom man benytter --continue-on-error eller -c så anbefales det å splitte byggloggene ved hjelp av --split-logs eller -l\\n
Dersom man savner noen applikasjoner kan de legges til i /home/vagrant/.build-akr/applikasjoner.cfg

${GRONN}Kjente feil:${INGEN_FARGE}
Tekstfilen /home/vagrant/.build-akr/applikasjoner.cfg MÅ redigeres i Unix grunnet newline-utfordringene\\ntil Microsoft. Rekkefølgen i nevnte fil blir default\\n
Formattering av output fungerer best i terminal som har >= 80 kolonner bredde

${GRONN}Konfigurasjonsfiler:${INGEN_FARGE}
/home/vagrant/.build-akr/applikasjoner.cfg\\n\\n
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

### Layout-funksjoner
flytt_cursor_opp() {
    printf "\\033[%qA" "${1}"
}

flytt_cursor_ned() {
    printf "\\033[%qB" "${1}"
}

flytt_cursor_frem() {
    printf "\\033[%qC" "${1}"
}

flytt_cursor_tilbake() {
    printf "\\033[%qD" "${1}"
}

lagre_cursorposisjon() {
    printf "\\033[s"
}

kall_lagret_cursorposisjon() {
    printf "\\033[u"
}

slett_til_slutten_av_linjen() {
    printf "\\033[0K"
}
### /Layout-funksjoner

### Generisk metode for å skrive ut advarsler
skriv_ut_advarsel() {
    printf "\\n%b*** %s *** %b\\n\\n" "${ROD}" "${1}" "${INGEN_FARGE}"
}

### Hjelpefunksjon for formattering av tekst
pad() {
    lengde=$1
    i=0
    while [ $i -lt $lengde ]; do
        printf "%s" "*"
        i=$(( i+1 ))
    done
}

### Oppsummering for Bob
summary() {
    bob_bold=$(tput bold)
    bob_normal=$(tput sgr0)
    printf "\t%-25s %-80s \n" "${bob_bold}bob build-akr:${bob_normal}" "Hjelpefunksjoner for bygging av akr-applikasjoner";
}

### Manual/Hjelpeside
usage() {
    printf "%b" "${BRUK}"
}

### Deklarerer applikasjonsdifferanse som er forskjellen på forventede og mottatte applikasjoner
forventede_applikasjoner() {
    applikasjonsdifferanse=()

    for i in "${!applikasjoner_fra_bruker[@]}"; do
        skip=

        for j in "${!applikasjoner_fra_config[@]}"; do
            if [ "${applikasjoner_fra_bruker[${i}]}" == "${applikasjoner_fra_config[${j}]}" ]; then
                skip=1
                break
            fi
        done

        [[ -n ${skip} ]] || applikasjonsdifferanse+=( "${applikasjoner_fra_bruker[$i]}" )

    done

    declare -a applikasjonsdifferanse
}

### Sorterer applikasjoner i henhold til rekkefølge i config
sorter_applikasjoner() {

    for i in "${!applikasjoner_fra_config[@]}"; do
        for j in "${!applikasjoner_fra_bruker[@]}"; do
            if [ "${applikasjoner_fra_config[${i}]}" == "${applikasjoner_fra_bruker[${j}]}" ]; then
                skip=1
                rekkefolge+=( "${applikasjoner_fra_config[$i]}" )
                break
            fi
        done
    done

    unset "applikasjoner_fra_config"
    applikasjoner_fra_config=( "${rekkefolge[@]}" )
    unset "skal_bygges"
}

### Parser applikasjoner gitt ved kommandolinjen, sammenligner med kjente applikasjoner
parse_applikasjoner_fra_cli() {
    IFS=',' read -r -a applikasjoner_fra_bruker <<< "${1}"

    if [ "${force}" -eq 0 ];then
        forventede_applikasjoner
        if [ "${#applikasjonsdifferanse[@]}" -gt 0 ]; then
            skriv_ut_advarsel "$(printf "Ukjent applikasjon %s" "${applikasjonsdifferanse[*]}")"
            exit 1
        fi

        sorter_applikasjoner

    else
        if [ "${#applikasjoner_fra_bruker[@]}" -gt 0 ]; then
            unset "applikasjoner_fra_config"
            applikasjoner_fra_config=( "${applikasjoner_fra_bruker[@]}" )
        else
            skriv_ut_advarsel "${INGEN_APPLIKASJONER}"
            exit 1
        fi
    fi
}

### Gjør formatet mer leselig ved lange mappenavn
trunker_applikasjonsnavn() {
    testtekstlengde=${2}
    applikasjon=${1}
    maks_lengde=$(( ${terminalbredde} - $(( ${testtekstlengde} + 6 )) ))
    if [[ ${maks_lengde} -lt 3 ]]; then
        printf "Terminalen er for smal til å gi fornuftig output. Resize til minimum ${min_terminalbredde} kolonner og prøv igjen.\\n"
        exit 1
    elif [[ ${maks_lengde} -gt ${#applikasjon} ]]; then
        export pretty_print="${applikasjon}"
    else
        export pretty_print="${applikasjon:0:$maks_lengde}..."
    fi
}

### Spinn-funksjonalitet
spinn_cursor() {
    pid=$1
    spinn="-\|/"
    i=0
    app=$4
    pretty=$6
    testString=$5

    flytt_cursor_frem $(( $terminalbredde - $(( ${#pretty} + ${#testString} + ${diverse_tekstgrumslengde} )) ))
    printf "%b" "${GRONN}"
    printf "%s" "${spinn:$i:1}"

    ### Sjekk om maven fortsatt bygger, spinn
    while kill -0 "${pid}" 2>/dev/null
    do
        i=$(( (i+1) %4 ))
        flytt_cursor_tilbake 1
	    printf "%s" "${spinn:${i}:1}"
        sleep .1
    done

    printf "%b" "${INGEN_FARGE}"
    wait "${pid}"

    ### Sjekk om bygget feiler, skriv ut advarsel og eventuelt avslutt
    if [ $? -ne 0 ]; then
        flytt_cursor_tilbake 2
        slett_til_slutten_av_linjen
        printf "%b%s%b" "${ROD}${BLINK}${BOLD}" "!!" "${INGEN_FARGE}\\n"

        if [ $continue -ne 1 ]; then
            printf "\\n\\n"
            tail -n 400 "${logg}"
            skriv_ut_advarsel "${BYGG_FEILET}" && exit 1
        else
            feilliste[$feilcount]="\\n\\nApplikasjon:\\t${app}\nLogg:\\t\\t${BOLD}${BLAA}${logg}${INGEN_FARGE}"
            feilcount=$(( feilcount+1 ))
        fi

    else
        flytt_cursor_tilbake 2
        slett_til_slutten_av_linjen
        printf "%b%s%b" "${GRONN}${BOLD}" "OK" "${INGEN_FARGE}\\n"
    fi

}

### Tekststrenger som omhandler tid brukt på bygg. Vis/ikke vis osv...
beregn_tid() {
    TID_BRUKT=$(( SECONDS - STARTTID))
    MINUTTER=$(( TID_BRUKT / 60 ))
    SEKUNDER=$(( TID_BRUKT % 60 ))

    if [ ${SEKUNDER} -eq 1 ]; then
        SEKUND_STRENG="1 sekund"
    elif [ ${SEKUNDER} -gt 1 ];then
        SEKUND_STRENG="${SEKUNDER} sekunder"
    fi

    if [ ${MINUTTER} -eq 1 ]; then
        MINUTT_STRENG="1 minutt"
    elif [ ${MINUTTER} -gt 1 ];then
        MINUTT_STRENG="${MINUTTER} minutter"
    fi

    [[ -n ${SEKUND_STRENG} && -n ${MINUTT_STRENG} ]] && MINUTT_STRENG="${MINUTT_STRENG} og "
}

### Selve options-parsingen. Gi variablene korrekte verdier i henhold til flagg og parametere
parse_options_og_gi_initielle_variabler_angitte_verdier() {
    options=$(getopt -o "sa:vzchfblnp:P:" -l "skip-tests,summary,fix-bugs,do-not-disturb,split-logs,verbose,continue-on-error,force,path:,profile:,applikasjoner:,help" -- "$@")
    eval set -- "${options}"

    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--applikasjoner) applikasjonsvalg="${2}" ; shift 2 ;;
            -P|--profile)
                    case "$2" in
                        jrebel) byggprofil="-Pjrebel" ; shift 2 ;;
                        it) byggprofil="-Pit" ; shift 2 ;;
                        *) skriv_ut_advarsel "${UKJENT_PROFIL}" && exit 1 ;;
                    esac ;;
            -f|--force) force=1 ; shift ;;
            -n|--do-not-disturb) dropp_notifikasjon=1 ; shift ;;
            -s|--skip-tests) skip_tester="-DskipTests" ; shift ;;
            -p|--path) path="${2}" ; shift 2 ;;
            -l|--split-logs) splitt_logg=1 ; shift ;;
            -c|--continue-on-error) continue=1 ; shift ;;
            -b|--fix-bugs) printf "%b" "${FIX}" && exit 0 ;;
            -v|--verbose) verbose=1 ; shift ;;
            -h|--help) usage && exit 0 ;;
            -z|--summary) summary && exit 0 ;;
            --) shift ; break ;;
            *) printf "%s" "$0: feil - ukjent flagg - prøv igjen $1" 1>&2; exit 1 ;;
        esac
    done
}

### Lagre cursor-posisjon i starten av linjen
sett_utgangspunkt_for_cursor_kalkulering() {
    printf "\\n"
    lagre_cursorposisjon
}

### Avgjør hvorvidt man har fått inn applikasjoner som skal bygges via cli
sjekk_om_applikasjoner_fra_cli_skal_parses() {
    ### Parse applikasjoner fra cli om nødvendig
    [[ -n "${applikasjonsvalg}" ]] && parse_applikasjoner_fra_cli "${applikasjonsvalg}"
}

### Sjekk om angitt filsti til akr eksisterer, magisk slash-funksjonalitet
sjekk_om_mappe_til_akr_eksisterer() {
    if [ -d "${path}" ]; then
        cd "${path}"
        absolutt_path=$(pwd)
    else
        skriv_ut_advarsel "${UGYLDIG_FILSTI}"
        exit 1
    fi
}

### Bygg hver angitte applikasjon/alle applikasjoner
bygg_angitte_eller_alle_applikasjoner() {
    for i in "${!applikasjoner_fra_config[@]}"; do
        [[ ${byggprofil} == "-Pit" && "${skip_tester}" != "-DskipTests" ]] && test_string=" med integrasjonstester" || test_string=""
        aktuell_applikasjon="${absolutt_path}"/"${applikasjoner_fra_config[$i]}"

        byggtekst=$(printf "* Bygg ${test_string}")
        trunker_applikasjonsnavn ${applikasjoner_fra_config[$i]} ${#byggtekst}

        if [ $splitt_logg -eq 1 ]; then
            logg="/tmp/"${applikasjoner_fra_config[$i]}"-bygg.log"
        fi

        ### Sjekk om gitt applikasjonsmappe eksisterer
        if [ -d  "${aktuell_applikasjon}" ]; then

            ### Dersom man herfra i scriptet ikke kan gå til mappen er det sannsynligvis et problem med rettigheter
            cd "${aktuell_applikasjon}" || (skriv_ut_advarsel "${RETTIGHETER}"; exit 1)

            ### Skjul output om verbose ikke er valgt, vis spinner istedet
            if [ ${verbose} -eq 0 ]; then
                printf "* Bygg %b%s%b%s" "${GRONN}" "${pretty_print}" "${INGEN_FARGE}" "${test_string}"
                mvn clean install ${byggprofil} ${skip_tester} 2> >(tee /tmp/akr-bygg-error.log >&2) &>"${logg}" & pid=$!
                spinn_cursor "${pid}" "${aktuell_applikasjon}" "${i}" "${applikasjoner_fra_config[$i]}" "${test_string}" "${pretty_print}"
            else
                mvn clean install ${byggprofil} ${skip_tester} > >(tee "${logg}" 2> >(tee /tmp/akr-bygg-error.log >&2)) & pid=$!
                wait "${pid}"
                if [ $? -ne 0 ]; then
                    if [ $continue -ne 1 ]; then
                        skriv_ut_advarsel "${BYGG_FEILET}" && exit 1
                    else
                        feilliste[$feilcount]="\\n\\nApplikasjon:\\t${applikasjoner_fra_config[$i]}\nLogg:\\t\\t${BOLD}${BLAA}${logg}${INGEN_FARGE}"
                        feilcount=$(( feilcount+1 ))
                    fi
                fi
            fi
            byggcount=$(( $byggcount + 1 ))
        else
            printf "* Mislyktes med bygging av %s" "${applikasjoner_fra_config[${i}]}"
            skriv_ut_advarsel "${IKKE_FUNNET}"
        fi

    done

}

### Lager en feilmelding ved behov
bygg_opp_feilmelding() {
    if [ ${feilcount} -gt 0 ]; then
        printf "\\n\\n"
        feil="Byggfeil"
        padlengde=$(( ($terminalbredde / 2) -  (${#feil} / 2) - 1 ))
        pad $padlengde
        printf " %b " "${ROD}${BOLD}${feil}${INGEN_FARGE}"
        pad $padlengde
        for i in "${!feilliste[@]}"; do
            printf "%b" "${feilliste[$i]}"
        done
        printf "\\n\\n"
        pad $terminalbredde
        printf "\\n"
        FEILTEKST=" med ${ROD}${BOLD}${feilcount} feil${INGEN_FARGE}..."
    fi
}

### Skriver ut oppsumeringstekst
skriv_ut_oppsummering_av_bygg() {
    if [ ${byggcount} -gt 0 ]; then
        ### Skriv ut potensiell gladmelding
        command -v notify-send > /dev/null 2>&1 && ([[ ${dropp_notifikasjon} -eq 0 ]] && notify-send -u normal -t 10000 -i terminal "Bygg Ferdig" "Bygget tok\\n<i>${MINUTT_STRENG}${SEKUND_STRENG}</i>")
        command -v osascript > /dev/null 2>&1 && ([[ ${dropp_notifikasjon} -eq 0 ]] && osascript -e "display notification \"Bygget tok ${MINUTT_STRENG}${SEKUND_STRENG}\" with title \"Bygg Ferdig\"")
        printf "%b%b%s%b%b" "\n\n" "${GRONN}${BOLD}" "Bygg ferdig" "${INGEN_FARGE}" " etter ${MINUTT_STRENG}${SEKUND_STRENG}${FEILTEKST}\\n\\n"
    else
        command -v notify-send > /dev/null 2>&1 && [[ ${dropp_notifikasjon} -eq 0 ]] && notify-send -u normal -t 10000 -i terminal "Ferdig" "Fant ingenting å  bygge"
        command -v osascript > /dev/null 2>&1 && ([[ ${dropp_notifikasjon} -eq 0 ]] && osascript -e "display notification \"Fant ingenting å bygge...\" with title \"Bygg Ferdig\"")
        printf "Fant ingenting å gjøre. Ingen applikasjoner ble bygd.\\n\\n"
    fi
}

#### Start script
kalkuler_terminalstorrelse
finn_working_directory
se_etter_cfg
parse_applikasjoner_fra_config
parse_options_og_gi_initielle_variabler_angitte_verdier "$@"
sett_utgangspunkt_for_cursor_kalkulering
sjekk_om_applikasjoner_fra_cli_skal_parses
sjekk_om_mappe_til_akr_eksisterer
bygg_angitte_eller_alle_applikasjoner
bygg_opp_feilmelding
beregn_tid
skriv_ut_oppsummering_av_bygg
### Slutt script
