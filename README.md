# IITB Internet Login

Login to the IITB internet using terminal without using GUI.
This script is work in progress and new features will be added soon.

## Usage

Curently, the script can be used to login, logout, show and change the credentials. The credentials are stored in a file in the home directory. The script will prompt for the credentials if they are not present in the file.

```bash
./internet.sh <command> [options]

Commands:
login                       Login to the iitb internet
logout                      Logout from the iitb internet
show                        Show the credentials
change                      Change the credentials

Options:
-h, --help                  Show this usage text
```

The login command can be used in any linux machine which has the `wget` and `grep` tool installed. But it is recommended to have `curl` installed. The logout command can only be used `curl` and requires `awk` and `sed` to be installed.

Some features that will be added soon are:

- [] Check if you are logged in and it is working.
- [] wget support for logout.
- [] Encrypt the credentials file.
- [] Shell autocompletion.

## Feedback

If you have any suggestions or feedback, please open an issue or send a pull request.
