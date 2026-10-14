#!/bin/bash
#
# IITB Internet Login script
# Author: Debojeet Das
#
echo -e "IITB Internet Login script"

set -o errexit
set -o nounset

CRED_DIR=/etc/iitb-login
CRED_FILE=$CRED_DIR/credentials.cred
CRED_NAME=iitb
ENV_FILE=$CRED_DIR/env
INSTALL_PATH=/usr/local/bin/iitb
UNIT_DIR=/etc/systemd/system
SERVICE=iitb-autologin.service
TIMER=iitb-autologin.timer

LOGIN_URL="https://internet-sso.iitb.ac.in/login.php"
PORTAL_URL="https://internet.iitb.ac.in"
CHECK_URL="http://connectivitycheck.gstatic.com/generate_204"
HC_URL="${IITB_HC_URL:-}"

USER_ID=
PASS=
CMD=
NEED_ROOT=0

NEEDED_TOOLS="wget grep awk sed systemd-creds"
RECOMMENDED_TOOLS="curl"

SELF=$(readlink -f "$0")
ORIG_ARGS=("$@")

die()
{
    echo -e "\e[1;31m$*\e[0m" >&2
    exit 1
}

check_prereq()
{
    for t in $NEEDED_TOOLS; do
        command -v "$t" > /dev/null || die "Missing required tools: $t"
    done
    command -v curl > /dev/null || command -v wget > /dev/null || die "Missing required tools: curl or wget"
}

need_root()
{
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "\e[1;36mRoot needed for the encrypted credentials, re-running with sudo...\e[0m"
        exec sudo -- "$SELF" "${ORIG_ARGS[@]}"
    fi
}

curl_cfg_escape()
{
    local s=${1//\\/\\\\}
    printf '%s' "${s//\"/\\\"}"
}

save_creds()
{
    (
        umask 077
        mkdir -p "$CRED_DIR"
        chmod 700 "$CRED_DIR"
        printf '%s:%s' "$USER_ID" "$PASS" | \
            systemd-creds encrypt --name="$CRED_NAME" - "$CRED_FILE.tmp"
        mv -f "$CRED_FILE.tmp" "$CRED_FILE"
    )
}

load_creds()
{
    local data
    if [ -n "${CREDENTIALS_DIRECTORY:-}" ] && [ -r "$CREDENTIALS_DIRECTORY/$CRED_NAME" ]; then
        # Running under systemd: already decrypted into a private in-memory dir
        data=$(cat "$CREDENTIALS_DIRECTORY/$CRED_NAME")
    else
        [ -f "$CRED_FILE" ] || die "User-Password not set. Run: iitb login"
        data=$(systemd-creds decrypt --name="$CRED_NAME" "$CRED_FILE" -) || \
            die "Could not decrypt $CRED_FILE (re-enter with: iitb change)"
    fi
    USER_ID=${data%%:*}
    PASS=${data#*:}
}

prompt_creds()
{
    read -rp "username: " USER_ID
    read -rsp "password: " PASS
    echo ""
    [ -n "$USER_ID" ] && [ -n "$PASS" ] || die "Username and password cannot be empty"
}

check_data()
{
    local legacy data
    if [ -f "$CRED_FILE" ]; then
        echo -e "User-Password already set. Continuing..."
        load_creds
        return
    fi

    # Import an old plaintext file if one is lying around
    for legacy in "$PWD/.internet.dat" "$CRED_DIR/credentials"; do
        if [ -f "$legacy" ]; then
            echo -e "\e[1;36mFound plaintext $legacy, importing into encrypted store...\e[0m"
            data=$(cat "$legacy")
            USER_ID=${data%%:*}
            PASS=${data#*:}
            save_creds
            echo -e "\e[1;33mImported. Now delete the plaintext copy: shred -u '$legacy'\e[0m"
            return
        fi
    done

    echo -e "\e[1;91mUser-Password not set. Please enter the details!\e[0m"
    prompt_creds
    save_creds
}

change_data()
{
    if [ -f "$CRED_FILE" ]; then
        echo -e "\e[1;36mChanging User-Password...\e[0m"
        prompt_creds
        save_creds
        echo -e "\e[1;32mChanged Password!\e[0m"
    else
        echo -e "\e[1;31mUser-Password not set.\e[0m"
        exit 1
    fi
}

show_data()
{
    if [ -f "$CRED_FILE" ]; then
        echo -e "Showing User-Password..."
        load_creds
        echo "$USER_ID:$PASS"
    else
        echo -e "\e[1;31mUser-Password not set.\e[0m"
        exit 1
    fi
}

portal_request()
{
    if command -v "$RECOMMENDED_TOOLS" > /dev/null; then
        printf 'user = "%s:%s"\n' "$(curl_cfg_escape "$USER_ID")" "$(curl_cfg_escape "$PASS")" | \
            curl -s -m 15 --location-trusted -K - "$LOGIN_URL" || true
    else
        wget -qO- -T 15 --auth-no-challenge \
            --config=<(printf 'user=%s\npassword=%s\n' "$USER_ID" "$PASS") \
            "$LOGIN_URL" || true
    fi
}

online()
{
    local code
    if command -v curl > /dev/null; then
        code=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "$CHECK_URL" 2>/dev/null) || true
        [ "$code" = "204" ]
    else
        wget -S -O /dev/null -T 8 "$CHECK_URL" 2>&1 | grep -q 'HTTP/[0-9.]* 204'
    fi
}

current_ip()
{
    curl -L --silent -m 15 "$PORTAL_URL" | grep "checked" | awk '{print $4}' | \
        awk '{split($0,a,"="); print a[2]}' | sed 's/"//g' || true
}

login()
{
    local resp
    check_data
    echo -e "Logging in..."
    if command -v "$RECOMMENDED_TOOLS" > /dev/null; then
        echo -e "Using curl"
    else
        echo -e "\e[1;36mUsing wget. Install curl!\e[0m"
    fi

    resp=$(portal_request)
    if grep -q "window.location.href" <<< "$resp"; then
        echo -e "\e[1;32mLogged in!\e[0m"
        return 0
    fi

    resp=$(portal_request)
    if grep -qF "$USER_ID" <<< "$resp"; then
        echo -e "\e[1;36mAlready logged in!\e[0m"
    else
        echo -e "\e[1;31mSomething is Wrong!!\e[0m"
        return 1
    fi
}

logout()
{
    local ip checkip
    command -v curl > /dev/null || die "logout needs curl"
    echo -e "Checking if logged in..."
    ip=$(current_ip)
    if [[ -z "$ip" ]]; then
        echo -e "\e[1;31mNot logged in!\e[0m"
        exit 1
    else
        curl -L --silent -X POST "$PORTAL_URL/logout.php" \
            -d "button=Logout&etype=rs&etype=rs&etype=rs&etype=rs&ip=$ip&etype=rs" > /dev/null || true
        checkip=$(current_ip)
        if [[ -z "$checkip" ]]; then
            echo -e "\e[1;32mLogged out!\e[0m"
        else
            echo -e "\e[1;31mSomething is Wrong!!\e[0m"
        fi
    fi
}

hc_ping()
{
    if [ -n "$HC_URL" ] && command -v curl > /dev/null; then
        curl -fsS -m 10 -o /dev/null "$HC_URL" || true
    fi
}

watchdog()
{
    local attempt
    if online; then
        hc_ping
        return 0
    fi

    load_creds
    echo "Internet down, logging in as $USER_ID"
    for attempt in 1 2 3; do
        portal_request > /dev/null
        sleep 5
        if online; then
            echo "Login ok (attempt $attempt)"
            hc_ping
            return 0
        fi
        echo "Attempt $attempt failed"
        sleep 10
    done
    echo "Still offline after 3 attempts"
    return 1
}

status()
{
    local ip
    if online; then
        echo -e "Internet: \e[1;32mup\e[0m"
    else
        echo -e "Internet: \e[1;31mdown\e[0m"
    fi
    if command -v curl > /dev/null; then
        ip=$(current_ip)
        if [ -n "$ip" ]; then echo "Portal:   logged in (IP $ip)"; else echo "Portal:   not logged in"; fi
    fi
    if [ -d "$CRED_DIR" ] && [ ! -x "$CRED_DIR" ]; then
        echo "Creds:    can't check as $(id -un) (run: sudo iitb status)"
    elif [ -f "$CRED_FILE" ]; then
        echo "Creds:    stored encrypted in $CRED_FILE"
    else
        echo "Creds:    not set"
    fi
    if systemctl is-active --quiet "$TIMER" 2> /dev/null; then
        echo -e "Watchdog: \e[1;32mactive\e[0m"
        systemctl list-timers --no-pager "$TIMER" | head -n 2
    else
        echo -e "Watchdog: \e[1;33minactive\e[0m (enable with: iitb enable)"
    fi
}

enable_service()
{
    [ -f "$CRED_FILE" ] || die "No credentials stored yet. Run: iitb login"

    [ "$SELF" = "$INSTALL_PATH" ] || install -m 755 "$SELF" "$INSTALL_PATH"

    cat > "$UNIT_DIR/$SERVICE" <<EOF
[Unit]
Description=IITB captive portal auto-login
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$INSTALL_PATH watch
# Throwaway unprivileged user; systemd decrypts the credential into a private in-memory dir
DynamicUser=yes
LoadCredentialEncrypted=$CRED_NAME:$CRED_FILE
EnvironmentFile=-$ENV_FILE
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
EOF

    cat > "$UNIT_DIR/$TIMER" <<EOF
[Unit]
Description=Check internet and re-login to IITB portal every 3 minutes

[Timer]
OnBootSec=30s
OnUnitActiveSec=3min
AccuracySec=15s

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$TIMER"
    echo -e "\e[1;32mWatchdog enabled (checks every 3 min).\e[0m Logs: journalctl -u $SERVICE"
}

disable_service()
{
    systemctl disable --now "$TIMER" 2> /dev/null || true
    rm -f "$UNIT_DIR/$SERVICE" "$UNIT_DIR/$TIMER"
    systemctl daemon-reload
    echo -e "\e[1;32mWatchdog disabled.\e[0m Credentials kept in $CRED_FILE"
}

# ---------------------------------------------------------------- cli
usage()
{
    local FULL=${1:-}

    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "login                     Login to the iitb internet"
    echo "logout                    Logout from the iitb internet"
    echo "show                      Show the credentials"
    echo "change                    Change the credentials"
    echo "status                    Show internet, portal and watchdog status"
    echo "enable                    Install and start the auto-login watchdog (systemd)"
    echo "disable                   Stop and remove the auto-login watchdog"
    echo "watch                     Check once and re-login if offline (used by the timer)"
    echo ""

    if [ -z "$FULL" ] ; then
        echo "Use --help to see the list of options."
        exit 1
    fi

    echo "Options:"
    echo "-h, --help                Show this usage text"
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
    login)   CMD=login;           NEED_ROOT=1 ;;
    logout)  CMD=logout ;;
    show)    CMD=show_data;       NEED_ROOT=1 ;;
    change)  CMD=change_data;     NEED_ROOT=1 ;;
    status)  CMD=status ;;
    enable)  CMD=enable_service;  NEED_ROOT=1 ;;
    disable) CMD=disable_service; NEED_ROOT=1 ;;
    watch)
        CMD=watchdog
        # Under systemd the credential is already decrypted for us; by hand we need root
        [ -n "${CREDENTIALS_DIRECTORY:-}" ] || NEED_ROOT=1
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
[ "$NEED_ROOT" -eq 1 ] && need_root
$CMD "$@"