#!/usr/bin/env bash

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
read -r -d '' USAGE << EOM
Builds maven projects in current or specified folder.

${GREEN}Usage:${NO_COLOUR}
mvn-dist [options]

${GREEN}Options:${NO_COLOUR}
$(display_options)

${GREEN}Examples:${NO_COLOUR}
Build all applications in /mnt/data/git
${BLUE}mvn-dist -p /mnt/data/git${NO_COLOUR}

Build only application named model without integration tests.
${BLUE}mvn-dist --skip-tests -a model${NO_COLOUR}

Build applications model, common and case, force to build in given order.
${BLUE}mvn-dist -a model,common,case -f${NO_COLOUR}

Build an application with a custom name.
${BLUE}mvn-dist -a monolith -f${NO_COLOUR}

Build all applications in /mnt/data/git with profile it,\\nContinue building the next application on build error and log separately.
${BLUE}mvn-dist -p /mnt/data/git -P it -c -l${NO_COLOUR}

${GREEN}Tip:${NO_COLOUR}
Use short flags when you need tab completion.
If utilizing --continue-on-error you should consider splitting logs using --split-logs.
Add applications to build in applications.cfg
Add build profiles in profiles.cfg

${GREEN}Known issues and quirks:${NO_COLOUR}
applications.cfg and its siblings should be edited using a UNIX flavour due to MS' new-line challenges.
Consider using a terminal with a minimum width of 80 to get decently formatted output.

${GREEN}Configuration files:${NO_COLOUR}
${mvn_dist_home}/${applications_cfg}
${mvn_dist_home}/${settings_cfg}
${mvn_dist_home}/${profiles_cfg}\\n\\n
EOM

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
