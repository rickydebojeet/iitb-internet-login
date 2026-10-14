# IITB Internet Login

Log in to the IITB internet from the terminal, without a browser. It can also keep a machine logged in automatically, which is useful for machines that must come back online on their own after a power cut, or that sit idle long enough for the portal to drop their session.

## Features

- Login, logout, show and change credentials from the terminal.
- Credentials are stored **encrypted** with `systemd-creds` (AES-256-GCM), never in plaintext, and are never passed on the command line where `ps` could see them.
- Optional **auto-login watchdog**: a systemd timer checks every 3 minutes whether the internet actually works and logs in again only when it doesn't (after a power cut, a reboot, an IP change or a portal session expiry).
- `status` command to see internet, portal and watchdog state at a glance.
- Optional dead-man alert via [healthchecks.io](https://healthchecks.io), so you get notified when a machine stays offline.
- Imports an old plaintext `.internet.dat` from earlier versions automatically.

## Requirements

- Linux with **systemd 250 or newer** (check with `systemctl --version`).
- `grep`, `awk`, `sed`, and `curl` (recommended) or `wget`.
- `sudo` access, since the encrypted credentials are readable only by root.

## Installation

```bash
chmod +x internet.sh
sudo install -m 755 internet.sh /usr/local/bin/iitb
```

The rest of this README uses the installed name `iitb`. Running `./internet.sh` directly works the same way.

## Usage

```bash
iitb <command> [options]

Commands:
login                     Login to the iitb internet
logout                    Logout from the iitb internet
show                      Show the credentials
change                    Change the credentials
status                    Show internet, portal and watchdog status
enable                    Install and start the auto-login watchdog (systemd)
disable                   Stop and remove the auto-login watchdog
watch                     Check once and re-login if offline (used by the timer)

Options:
-h, --help                Show this usage text
```

### First login

```bash
iitb login
```

You are prompted for your LDAP username and password once (the hash from sso site). They are encrypted to `/etc/iitb-login/credentials.cred` and reused from then on.

If an old plaintext `.internet.dat` exists in the current directory, it is imported and encrypted instead of prompting. Delete the plaintext copy afterwards:

```bash
shred -u .internet.dat
```

### Staying logged in automatically

```bash
iitb enable
```

This installs `iitb-autologin.service` and `iitb-autologin.timer`. The timer runs 30 seconds after boot and then every 3 minutes. Each run checks `connectivitycheck.gstatic.com/generate_204` and only logs in (up to 3 attempts) if the check fails.

```bash
iitb status                              # quick overview
journalctl -u iitb-autologin -f          # live logs
iitb disable                             # remove the watchdog (credentials are kept)
```

## How secure are the credentials?

The encryption key is either a root-only host key (`/var/lib/systemd/credential.secret`), a key sealed in the machine's TPM2 chip, or both. `systemd-creds` picks both automatically when a TPM2 is available.

- **Protected against:** other users on the machine, accidentally printing the file, and copies of `/etc` in backups or git. With a TPM2, also against copying the disk to another machine.
- **Not protected against:** root on the same machine. Unattended login means the machine must be able to decrypt the password without you, so root always can.

## Feedback

If you have any suggestions or feedback, please open an issue or send a pull request.