# mvn-dist
Script for building (distributed) maven projects. _mvn_ needs to be installed and available in $PATH.

Builds maven projects in current or specified folder.

Usage:
mvn-dist [options]

## Options
```bash
Builds maven projects in current or specified folder.

Usage:
mvn-dist [options]

Options:
-l, --split-logs            Split log for each application. Makes sense when 
                            utilizing -c|--continue-on-error. 
-e, --examples              Show usage examples. 
-s, --skip-tests            Do not run integration tests. 
-h, --help                  This help page. 
-p, --path=/path/to/source  Path to the folder holding the applications to 
                            build. 
-c, --continue-on-error     Continue building the next application on build 
                            failure. 
-f, --force                 Force mvn-dist to build applications provided by 
                            -a|--applications in given order. This also 
                            supports custom names of folders holding the 
                            applications. 
-v, --verbose               Print full Maven output. 
-n, --do-not-disturb        Do not disturb when build is finished. 
-a, --applications          Comma separated list of applications to build. 
```

## Usage
```
Examples:
Build all applications in /mnt/data/git
mvn-dist -p /mnt/data/git

Build only application named model without integration tests.
mvn-dist --skip-tests -a model

Build applications model, common and case, force to build in given order.
mvn-dist -a model,common,case -f

Build an application with a custom name.
mvn-dist -a monolith -f

Build all applications in /mnt/data/git,
Continue building the next application on build error and log separately.
mvn-dist -p /mnt/data/git -c -l

Tip:
Use short flags when you need tab completion.
If utilizing --continue-on-error you should consider splitting logs using --split-logs.
Add applications to build in applications.cfg

Known issues and quirks:
applications.cfg and its siblings should be edited using a UNIX flavour due to MS' new-line challenges.
Consider using a terminal with a minimum width of 80 to get decently formatted output.

Configuration files:
${HOME}/.mvn-dist/applications.cfg
${HOME}/.mvn-dist/settings.cfg
```
