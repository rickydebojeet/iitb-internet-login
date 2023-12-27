#!/bin/bash
#
# Features to be added 
# curl -L -X POST "https://internet.iitb.ac.in/logout.php" -d "button=Logout&etype=rs&etype=rs&etype=rs&etype=rs&ip=10.14.22.240&etype=rs"
#
echo -e "IITB Internet Login script"

set -o errexit
set -o nounset

USER=
PASS=
CMD=

NEEDED_TOOLS="wget"
RECOMMENDED_TOOLS="curl"

check_prereq()
{
    for t in $NEEDED_TOOLS; do
        which "$t" > /dev/null || die "Missing required tools: $t"
    done
}

check_data()
{
    if [ -f "$PWD/.internet.dat" ]; then
        echo -e "User-Password already set. Continuing..."
        # reading from the .internet.dat file
        USER=$(cut -d: -f1 "$PWD/.internet.dat")
        PASS=$(cut -d: -f2 "$PWD/.internet.dat")
    else
        echo -e "\e[1;91mUser-Password not set. Please enter the details!\e[0m"
        read -p "username: " USER
        read -sp "password: " PASS
        echo ""
        echo "$USER:$PASS" > "$PWD/.internet.dat"
    fi
}

change_data()
{
    if [ -f "$PWD/.internet.dat" ]; then
        echo -e "\e[1;36mChanging User-Password...\e[0m"
        read -p "username: " USER
        read -sp "password: " PASS
        echo ""
        echo "$USER:$PASS" > "$PWD/.internet.dat"
        echo -e "\e[1;32mChanged Password!\e[0m"

    else
        echo -e "\e[1;31mUser-Password not set.\e[0m"
        exit 1
    fi
}

show_data()
{
    if [ -f "$PWD/.internet.dat" ]; then
        echo -e "Showing User-Password..."
        cat "$PWD/.internet.dat"
    else
        echo -e "\e[1;31mUser-Password not set.\e[0m"
        exit 1
    fi
}

login ()
{
    check_data
    echo -e "Logging in..."
    if  which "$RECOMMENDED_TOOLS" > /dev/null ; then
        echo -e "Using curl"
        curl -s --location-trusted -u "$USER:$PASS" "https://internet-sso.iitb.ac.in/login.php" | \
        grep -q window.location.href && \
        echo -e "\e[1;32mLogged in!\e[0m" && exit 0 || \
        curl -s --location-trusted -u "$USER:$PASS" "https://internet-sso.iitb.ac.in/login.php" | \
        grep -q $USER && \
        echo -e "\e[1;36mAlready logged in!\e[0m" || \
        echo -e "\e[1;31mSomething is Wrong!!\e[0m"
    else
        echo -e "\e[1;36mUsing wget. Install curl!\e[0m"
        wget -qO- --user="$USER" --password="$PASS" --auth-no-challenge "https://internet-sso.iitb.ac.in/login.php" | \
        grep -q window.location.href && \
        echo -e "\e[1;32mLogged in!\e[0m" && exit 0|| \
        wget -qO- --user="$USER" --password="$PASS" --auth-no-challenge "https://internet-sso.iitb.ac.in/login.php" | \
        grep -q $USER && \
        echo -e "\e[1;36mAlready logged in!\e[0m" || \
        echo -e "\e[1;31mSomething is Wrong!!\e[0m"
    fi
}

usage()
{
    local FULL=${1:-}

    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "login                     Run the website in your localhost"
    echo "show                      Show the credentials"
    echo "change                    Change the credentials"
    echo ""

    if [ -z "$FULL" ] ; then
        echo "Use --help to see the list of options."
        exit 1
    fi

    echo "Options:"
    echo "-h, --help                        Show this usage text"
    echo ""
    exit 1
}

OPTS="h"
LONGOPTS="help"

OPTIONS=$(getopt -o "$OPTS" --long "$LONGOPTS" -- "$@")
[ "$?" -ne "0" ] && usage >&2 || true

eval set -- "$OPTIONS"


while true; do
    arg="$1"
    shift

    case "$arg" in
        -h | --help)
            usage full >&2
            ;;
        -- )
            break
            ;;
    esac
done

[ "$#" -eq 0 ] && usage >&2

case "$1" in
    login)
        CMD=login
        ;;
    show)
        CMD=show_data
        ;;
    change)
        CMD=change_data
        ;;
    "help")
        usage full >&2
        ;;
    *)
        usage >&2
        ;;
esac

shift
check_prereq
$CMD "$@"
