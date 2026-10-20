 #!/usr/bin/env bash
#
# Try `install_namyudp.sh --help` for usage.
#
# (c) 2023 Namydev
#

set -e


###
# SCRIPT CONFIGURATION
###

# Domain Name
DOMAIN="${DOMAIN:-vpn.namydev.com}"

# PROTOCOL
PROTOCOL="udp"

# UDP PORT
UDP_PORT="${UDP_PORT:-:36712}"

# OBFS
OBFS="${OBFS:-namyudp}"

# PASSWORDS
PASSWORD="${PASSWORD:-namyudp}"

# Basename of this script
SCRIPT_NAME="$(basename "$0")"

# Command line arguments of this script
SCRIPT_ARGS=("$@")

# Path for installing executable
EXECUTABLE_INSTALL_PATH="/usr/local/bin/hysteria"

# Paths to install systemd files
SYSTEMD_SERVICES_DIR="/etc/systemd/system"

# Directory to store hysteria config file
CONFIG_DIR="/etc/hysteria"
USER_MANAGER_PATH="/usr/local/bin/namyudp-user"

# URLs of GitHub
REPO_URL="https://github.com/apernet/hysteria"
API_BASE_URL="https://api.github.com/repos/apernet/hysteria"

# curl command line flags.
# To using a proxy, please specify ALL_PROXY in the environ variable, such like:
# export ALL_PROXY=socks5h://192.0.2.1:1080
CURL_FLAGS=(-L -f -q --retry 5 --retry-delay 10 --retry-max-time 60)


###
# AUTO DETECTED GLOBAL VARIABLE
###

# Package manager
PACKAGE_MANAGEMENT_INSTALL="${PACKAGE_MANAGEMENT_INSTALL:-}"

# Operating System of current machine, supported: linux
OPERATING_SYSTEM="${OPERATING_SYSTEM:-}"

# Architecture of current machine, supported: 386, amd64, arm, arm64, mipsle, s390x
ARCHITECTURE="${ARCHITECTURE:-}"

# User for running hysteria
HYSTERIA_USER="${HYSTERIA_USER:-}"

# Directory for ACME certificates storage
HYSTERIA_HOME_DIR="${HYSTERIA_HOME_DIR:-}"


###
# ARGUMENTS
###

# Supported operation: install, remove, check_update
OPERATION=

# User specified version to install
VERSION=

# Force install even if installed
FORCE=

# User specified binary to install
LOCAL_FILE=


###
# COMMAND REPLACEMENT & UTILITIES
###

has_command() {
	local _command=$1
	
	type -P "$_command" > /dev/null 2>&1
}

curl() {
	command curl "${CURL_FLAGS[@]}" "$@"
}

mktemp() {
	command mktemp "$@" "hyservinst.XXXXXXXXXX"
}

tput() {
	if has_command tput; then
		command tput "$@"
		fi
}

tred() {
	tput setaf 1
}

tgreen() {
	tput setaf 2
}

tyellow() {
	tput setaf 3
}

tblue() {
	tput setaf 4
}

taoi() {
	tput setaf 6
}

tbold() {
	tput bold
}

treset() {
	tput sgr0
}

note() {
	local _msg="$1"
	
	echo -e "$SCRIPT_NAME: $(tbold)note: $_msg$(treset)"
}

warning() {
	local _msg="$1"
	
	echo -e "$SCRIPT_NAME: $(tyellow)warning: $_msg$(treset)"
}

error() {
	local _msg="$1"
	
	echo -e "$SCRIPT_NAME: $(tred)error: $_msg$(treset)"
}

has_prefix() {
	local _s="$1"
	local _prefix="$2"
	
	if [[ -z "$_prefix" ]]; then
		return 0
		fi
		
		if [[ -z "$_s" ]]; then
			return 1
			fi
			
			[[ "x$_s" != "x${_s#"$_prefix"}" ]]
}

systemctl() {
	if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]] || ! has_command systemctl; then
		return
		fi
		
		command systemctl "$@"
}

show_argument_error_and_exit() {
	local _error_msg="$1"
	
	error "$_error_msg"
	echo "Try \"$0 --help\" for the usage." >&2
	exit 22
}

install_content() {
	local _install_flags="$1"
	local _content="$2"
	local _destination="$3"
	
	local _tmpfile="$(mktemp)"
	
	echo -ne "Install $_destination ... "
	echo "$_content" > "$_tmpfile"
	if install "$_install_flags" "$_tmpfile" "$_destination"; then
		echo -e "ok"
		fi
		
		rm -f "$_tmpfile"
}

remove_file() {
	local _target="$1"
	
	echo -ne "Remove $_target ... "
	if rm "$_target"; then
		echo -e "ok"
		fi
}

exec_sudo() {
	# exec sudo with configurable environ preserved.
	local _saved_ifs="$IFS"
	IFS=$'\n'
	local _preserved_env=(
		$(env | grep "^PACKAGE_MANAGEMENT_INSTALL=" || true)
		$(env | grep "^OPERATING_SYSTEM=" || true)
		$(env | grep "^ARCHITECTURE=" || true)
		$(env | grep "^HYSTERIA_\w*=" || true)
		$(env | grep "^FORCE_\w*=" || true)
	)
	IFS="$_saved_ifs"
	
	exec sudo env \
	"${_preserved_env[@]}" \
	"$@"
}

detect_package_manager() {
	if [[ -n "$PACKAGE_MANAGEMENT_INSTALL" ]]; then
		return 0
		fi
		
		if has_command apt; then
			PACKAGE_MANAGEMENT_INSTALL='apt update; apt -y install'
			return 0
			fi
			
			if has_command dnf; then
				PACKAGE_MANAGEMENT_INSTALL='dnf check-update; dnf -y install'
				return 0
				fi
				
				if has_command yum; then
					PACKAGE_MANAGEMENT_INSTALL='yum update; yum -y install'
					return 0
					fi
					
					if has_command zypper; then
						PACKAGE_MANAGEMENT_INSTALL='zypper update; zypper install -y --no-recommends'
						return 0
						fi
						
						if has_command pacman; then
							PACKAGE_MANAGEMENT_INSTALL='pacman -Syu; pacman -Syu --noconfirm'
							return 0
							fi
							
							return 1
}

install_software() {
	local _package_name="$1"
	
	if ! detect_package_manager; then
		error "Supported package manager is not detected, please install the following package manually:"
		echo
		echo -e "\t* $_package_name"
		echo
		exit 65
		fi
		
		echo "Installing missing dependence '$_package_name' with '$PACKAGE_MANAGEMENT_INSTALL' ... "
		if $PACKAGE_MANAGEMENT_INSTALL "$_package_name"; then
			echo "ok"
			else
				error "Cannot install '$_package_name' with detected package manager, please install it manually."
				exit 65
				fi
}

is_user_exists() {
	local _user="$1"
	
	id "$_user" > /dev/null 2>&1
}

check_permission() {
	if [[ "$UID" -eq '0' ]]; then
		return
		fi
		
		note "The user currently executing this script is not root."
		
		case "$FORCE_NO_ROOT" in
		'1')
		warning "FORCE_NO_ROOT=1 is specified, we will process without root and you may encounter the insufficient privilege error."
		;;
	*)
	if has_command sudo; then
		note "Re-running this script with sudo, you can also specify FORCE_NO_ROOT=1 to force this script running with current user."
		exec_sudo "$0" "${SCRIPT_ARGS[@]}"
		else
			error "Please run this script with root or specify FORCE_NO_ROOT=1 to force this script running with current user."
			exit 13
			fi
			;;
		esac
}

check_environment_operating_system() {
	if [[ -n "$OPERATING_SYSTEM" ]]; then
		warning "OPERATING_SYSTEM=$OPERATING_SYSTEM is specified, opreating system detection will not be perform."
		return
		fi
		
		if [[ "x$(uname)" == "xLinux" ]]; then
			OPERATING_SYSTEM=linux
			return
			fi
			
			error "This script only supports Linux."
			note "Specify OPERATING_SYSTEM=[linux|darwin|freebsd|windows] to bypass this check and force this script running on this $(uname)."
			exit 95
}

check_environment_architecture() {
	if [[ -n "$ARCHITECTURE" ]]; then
		warning "ARCHITECTURE=$ARCHITECTURE is specified, architecture detection will not be performed."
		return
		fi
		
		case "$(uname -m)" in
		'i386' | 'i686')
		ARCHITECTURE='386'
		;;
	'amd64' | 'x86_64')
	ARCHITECTURE='amd64'
	;;
	'armv5tel' | 'armv6l' | 'armv7' | 'armv7l')
	ARCHITECTURE='arm'
	;;
	'armv8' | 'aarch64')
	ARCHITECTURE='arm64'
	;;
	'mips' | 'mipsle' | 'mips64' | 'mips64le')
	ARCHITECTURE='mipsle'
	;;
	's390x')
	ARCHITECTURE='s390x'
	;;
	*)
	error "The architecture '$(uname -a)' is not supported."
	note "Specify ARCHITECTURE=<architecture> to bypass this check and force this script running on this $(uname -m)."
	exit 8
	;;
	esac
}

check_environment_systemd() {
	if [[ -d "/run/systemd/system" ]] || grep -q systemd <(ls -l /sbin/init); then
		return
		fi
		
		case "$FORCE_NO_SYSTEMD" in
		'1')
		warning "FORCE_NO_SYSTEMD=1 is specified, we will process as normal even if systemd is not detected by us."
		;;
	'2')
	warning "FORCE_NO_SYSTEMD=2 is specified, we will process but all systemd related command will not be executed."
	;;
	*)
	error "This script only supports Linux distributions with systemd."
	note "Specify FORCE_NO_SYSTEMD=1 to disable this check and force this script running as systemd is detected."
	note "Specify FORCE_NO_SYSTEMD=2 to disable this check along with all systemd related commands."
	;;
	esac
}

check_environment_curl() {
	if has_command curl; then
		return
		fi
		apt update; apt -y install curl
}

check_environment_grep() {
	if has_command grep; then
		return
		fi
		apt update; apt -y install grep
}

check_environment() {
	check_environment_operating_system
	check_environment_architecture
	check_environment_systemd
	check_environment_curl
	check_environment_grep
}

vercmp_segment() {
	local _lhs="$1"
	local _rhs="$2"
	
	if [[ "x$_lhs" == "x$_rhs" ]]; then
		echo 0
		return
		fi
		if [[ -z "$_lhs" ]]; then
			echo -1
			return
			fi
			if [[ -z "$_rhs" ]]; then
				echo 1
				return
				fi
				
				local _lhs_num="${_lhs//[A-Za-z]*/}"
				local _rhs_num="${_rhs//[A-Za-z]*/}"
				
				if [[ "x$_lhs_num" == "x$_rhs_num" ]]; then
					echo 0
					return
					fi
					if [[ -z "$_lhs_num" ]]; then
						echo -1
						return
						fi
						if [[ -z "$_rhs_num" ]]; then
							echo 1
							return
							fi
							local _numcmp=$(($_lhs_num - $_rhs_num))
							if [[ "$_numcmp" -ne 0 ]]; then
								echo "$_numcmp"
								return
								fi
								
								local _lhs_suffix="${_lhs#"$_lhs_num"}"
								local _rhs_suffix="${_rhs#"$_rhs_num"}"
								
								if [[ "x$_lhs_suffix" == "x$_rhs_suffix" ]]; then
									echo 0
									return
									fi
									if [[ -z "$_lhs_suffix" ]]; then
										echo 1
										return
										fi
										if [[ -z "$_rhs_suffix" ]]; then
											echo -1
											return
											fi
											if [[ "$_lhs_suffix" < "$_rhs_suffix" ]]; then
												echo -1
												return
												fi
												echo 1
}

vercmp() {
	local _lhs=${1#v}
	local _rhs=${2#v}
	
	while [[ -n "$_lhs" && -n "$_rhs" ]]; do
		local _clhs="${_lhs/.*/}"
		local _crhs="${_rhs/.*/}"
		
		local _segcmp="$(vercmp_segment "$_clhs" "$_crhs")"
		if [[ "$_segcmp" -ne 0 ]]; then
			echo "$_segcmp"
			return
			fi
			
			_lhs="${_lhs#"$_clhs"}"
			_lhs="${_lhs#.}"
			_rhs="${_rhs#"$_crhs"}"
			_rhs="${_rhs#.}"
			done
			
			if [[ "x$_lhs" == "x$_rhs" ]]; then
				echo 0
				return
				fi
				
				if [[ -z "$_lhs" ]]; then
					echo -1
					return
					fi
					
					if [[ -z "$_rhs" ]]; then
						echo 1
						return
						fi
						
						return
}

check_hysteria_user() {
	local _default_hysteria_user="$1"
	
	if [[ -n "$HYSTERIA_USER" ]]; then
		return
		fi
		
		if [[ ! -e "$SYSTEMD_SERVICES_DIR/hysteria-server.service" ]]; then
			HYSTERIA_USER="$_default_hysteria_user"
			return
			fi
			
			HYSTERIA_USER="$(grep -o '^User=\w*' "$SYSTEMD_SERVICES_DIR/hysteria-server.service" | tail -1 | cut -d '=' -f 2 || true)"
			
			if [[ -z "$HYSTERIA_USER" ]]; then
				HYSTERIA_USER="$_default_hysteria_user"
				fi
}

check_hysteria_homedir() {
	local _default_hysteria_homedir="$1"
	
	if [[ -n "$HYSTERIA_HOME_DIR" ]]; then
		return
		fi
		
		if ! is_user_exists "$HYSTERIA_USER"; then
			HYSTERIA_HOME_DIR="$_default_hysteria_homedir"
			return
			fi
			
			HYSTERIA_HOME_DIR="$(eval echo ~"$HYSTERIA_USER")"
}


###
# ARGUMENTS PARSER
###

show_usage_and_exit() {
	echo
	echo -e "\t$(tbold)$SCRIPT_NAME$(treset) - NAMY-UDP server install script"
	echo
	echo -e "Usage:"
	echo
	echo -e "$(tbold)Install NAMY-UDP$(treset)"
	echo -e "\t$0 [ -f | -l <file> | --version <version> ]"
	echo -e "Flags:"
	echo -e "\t-f, --force\tForce re-install latest or specified version even if it has been installed."
	echo -e "\t-l, --local <file>\tInstall specified NAMY-UDP binary instead of download it."
	echo -e "\t--version <version>\tInstall specified version instead of the latest."
	echo
	echo -e "$(tbold)Remove NAMY-UDP$(treset)"
	echo -e "\t$0 --remove"
	echo
	echo -e "$(tbold)Check for the update$(treset)"
	echo -e "\t$0 -c"
	echo -e "\t$0 --check"
	echo
	echo -e "$(tbold)Show this help$(treset)"
	echo -e "\t$0 -h"
	echo -e "\t$0 --help"
	exit 0
}

parse_arguments() {
	while [[ "$#" -gt '0' ]]; do
		case "$1" in
		'--remove')
		if [[ -n "$OPERATION" && "$OPERATION" != 'remove' ]]; then
			show_argument_error_and_exit "Option '--remove' is conflicted with other options."
			fi
			OPERATION='remove'
			;;
		'--version')
		VERSION="$2"
		if [[ -z "$VERSION" ]]; then
			show_argument_error_and_exit "Please specify the version for option '--version'."
			fi
			shift
			if ! has_prefix "$VERSION" 'v'; then
				show_argument_error_and_exit "Version numbers should begin with 'v' (such like 'v1.3.1'), got '$VERSION'"
				fi
				;;
			 
			'-h' | '--help')
			show_usage_and_exit
			;;
			'-l' | '--local')
			LOCAL_FILE="$2"
			if [[ -z "$LOCAL_FILE" ]]; then
				show_argument_error_and_exit "Please specify the local binary to install for option '-l' or '--local'."
				fi
				break
				;;
			*)
			show_argument_error_and_exit "Unknown option '$1'"
			;;
			esac
			shift
			done
			
			if [[ -z "$OPERATION" ]]; then
				OPERATION='install'
				fi
				
				# validate arguments
				case "$OPERATION" in
				'install')
				if [[ -n "$VERSION" && -n "$LOCAL_FILE" ]]; then
					show_argument_error_and_exit '--version and --local cannot be specified together.'
					fi
					;;
				*)
				if [[ -n "$VERSION" ]]; then
					show_argument_error_and_exit "--version is only avaiable when install."
					fi
					if [[ -n "$LOCAL_FILE" ]]; then
						show_argument_error_and_exit "--local is only avaiable when install."
						fi
						;;
					esac
}


###
# FILE TEMPLATES
###

# /etc/systemd/system/hysteria-server.service
tpl_hysteria_server_service_base() {
  local _config_name="$1"

  cat << EOF
[Unit]
Description=NAMY-UDP Service
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/etc/hysteria
Environment="PATH=/usr/local/bin/hysteria"
ExecStart=/usr/local/bin/hysteria -config /etc/hysteria/config.json server

[Install]
WantedBy=multi-user.target
EOF
}

# /etc/systemd/system/hysteria-server.service
tpl_hysteria_server_service() {
  tpl_hysteria_server_service_base 'config'
}

# /etc/systemd/system/hysteria-server@.service
tpl_hysteria_server_x_service() {
  tpl_hysteria_server_service_base '%i'
}

# /etc/hysteria/config.json
tpl_etc_hysteria_config_json() {
  cat << EOF
{
  "server": "vpn.namydev.com",
   "listen": "$UDP_PORT",
  "protocol": "$PROTOCOL",
  "cert": "/etc/hysteria/hysteria.server.crt",
  "key": "/etc/hysteria/hysteria.server.key",
  "up": "100 Mbps",
  "up_mbps": 100,
  "down": "100 Mbps",
  "down_mbps": 100,
  "disable_udp": false,
  "obfs": "$OBFS",
  "auth": {
	"mode": "passwords",
	"config": ["$PASSWORD"]
         }
}
EOF
}


###
# SYSTEMD
###

get_running_services() {
	if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]]; then
		return
		fi
		
		systemctl list-units --state=active --plain --no-legend \
		| grep -o "hysteria-server@*[^\s]*.service" || true
}

restart_running_services() {
	if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]]; then
		return
		fi
		
		echo "Restarting running service ... "
		
		for service in $(get_running_services); do
			echo -ne "Restarting $service ... "
			systemctl restart "$service"
			echo "done"
			done
}

stop_running_services() {
	if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]]; then
		return
		fi
		
		echo "Stopping running service ... "
		
		for service in $(get_running_services); do
			echo -ne "Stopping $service ... "
			systemctl stop "$service"
			echo "done"
			done
}


###
# HYSTERIA & GITHUB API
###

is_hysteria_installed() {
	# RETURN VALUE
	# 0: hysteria is installed
	# 1: hysteria is not installed
	
	if [[ -f "$EXECUTABLE_INSTALL_PATH" || -h "$EXECUTABLE_INSTALL_PATH" ]]; then
		return 0
		fi
		return 1
}

get_installed_version() {
	if is_hysteria_installed; then
		"$EXECUTABLE_INSTALL_PATH" -v | cut -d ' ' -f 3
		fi
}

get_latest_version() {
	if [[ -n "$VERSION" ]]; then
		echo "$VERSION"
		return
		fi
		
		local _tmpfile=$(mktemp)
		if ! curl -sS -H 'Accept: application/vnd.github.v3+json' "$API_BASE_URL/releases/latest" -o "$_tmpfile"; then
			error "Failed to get latest release, please check your network."
			exit 11
			fi
			
			local _latest_version=$(grep 'tag_name' "$_tmpfile" | head -1 | grep -o '"v.*"')
			_latest_version=${_latest_version#'"'}
			_latest_version=${_latest_version%'"'}
			
			if [[ -n "$_latest_version" ]]; then
				echo "$_latest_version"
				fi
				
				rm -f "$_tmpfile"
}

download_hysteria() {
	local _version="$1"
	local _destination="$2"
	
	local _download_url="$REPO_URL/releases/download/v1.3.5/hysteria-$OPERATING_SYSTEM-$ARCHITECTURE"
	echo "Downloading hysteria archive: $_download_url ..."
	if ! curl -R -H 'Cache-Control: no-cache' "$_download_url" -o "$_destination"; then
		error "Download failed! Please check your network and try again."
		return 11
		fi
		return 0
}

 

###
# ENTRY
###

perform_install_hysteria_binary() {
	if [[ -n "$LOCAL_FILE" ]]; then
		note "Performing local install: $LOCAL_FILE"
		
		echo -ne "Installing hysteria executable ... "
		
		if install -Dm755 "$LOCAL_FILE" "$EXECUTABLE_INSTALL_PATH"; then
			echo "ok"
			else
				exit 2
				fi
				
				return
				fi
				
				local _tmpfile=$(mktemp)
				
				if ! download_hysteria "$VERSION" "$_tmpfile"; then
					rm -f "$_tmpfile"
					exit 11
					fi
					
					echo -ne "Installing hysteria executable ... "
					
					if install -Dm755 "$_tmpfile" "$EXECUTABLE_INSTALL_PATH"; then
						echo "ok"
						else
							exit 13
							fi
							
							rm -f "$_tmpfile"
}

perform_remove_hysteria_binary() {
	remove_file "$EXECUTABLE_INSTALL_PATH"
}

perform_install_hysteria_example_config() {
install_content -Dm644 "$(tpl_etc_hysteria_config_json)" "$CONFIG_DIR/config.json" ""
 
}

perform_install_hysteria_systemd() {
	if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]]; then
		return
		fi
		
		install_content -Dm644 "$(tpl_hysteria_server_service)" "$SYSTEMD_SERVICES_DIR/hysteria-server.service"
		install_content -Dm644 "$(tpl_hysteria_server_x_service)" "$SYSTEMD_SERVICES_DIR/hysteria-server@.service"
		
		systemctl daemon-reload
}

perform_remove_hysteria_systemd() {
	remove_file "$SYSTEMD_SERVICES_DIR/hysteria-server.service"
	remove_file "$SYSTEMD_SERVICES_DIR/hysteria-server@.service"
	
	systemctl daemon-reload
}

perform_install_hysteria_home_legacy() {
	if ! is_user_exists "$HYSTERIA_USER"; then
		echo -ne "Creating user $HYSTERIA_USER ... "
		useradd -r -d "$HYSTERIA_HOME_DIR" -m "$HYSTERIA_USER"
		echo "ok"
		fi
}

perform_install_user_manager() {
  install -d -m 700 "$CONFIG_DIR"
  if [[ ! -f "$CONFIG_DIR/users.json" ]]; then
    python3 - "$PASSWORD" <<'SEED_USERS'
import json, pathlib, sys, time
path=pathlib.Path('/etc/hysteria/users.json')
path.write_text(json.dumps({'admin': {'password':sys.argv[1], 'expires_at':0, 'allowed_ip':''}}, indent=2)+'\n')
path.chmod(0o600)
SEED_USERS
  fi
  cat > "$USER_MANAGER_PATH" <<'NAMYUDP_USER_MANAGER'
#!/usr/bin/env bash
set -euo pipefail
CONFIG=/etc/hysteria/config.json
USERS=/etc/hysteria/users.json
SERVICE=hysteria-server.service
MANAGER=/usr/local/bin/namyudp-user
CRON=/etc/cron.d/namyudp-expiry

[[ $EUID -eq 0 ]] || { echo 'Jalankan dengan root: sudo namyudp-user'; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo 'Python3 belum terpasang.'; exit 1; }

sync_auth() {
  python3 - <<'PY_SYNC'
import json, pathlib, os, tempfile, sys, time
cp=pathlib.Path('/etc/hysteria/config.json'); up=pathlib.Path('/etc/hysteria/users.json')
if not cp.exists() or not up.exists(): sys.exit('File konfigurasi/akun tidak ditemukan.')
users=json.loads(up.read_text()); now=time.time(); changed=False
# Migrate legacy {username: "password"} entries to structured records.
for name, value in list(users.items()):
    if isinstance(value, str):
        users[name]={'password':value,'expires_at':0,'allowed_ip':''}; changed=True
# Remove expired users (expires_at=0 means unlimited).
for name, value in list(users.items()):
    expiry=int(value.get('expires_at') or 0)
    if expiry and expiry <= now:
        del users[name]; changed=True
cfg=json.loads(cp.read_text()); auth=cfg.setdefault('auth', {})
if auth.get('mode') != 'passwords': sys.exit("Auth config bukan mode 'passwords'; konfigurasi tidak diubah.")
passwords=list(dict.fromkeys(str(v['password']) for v in users.values() if v.get('password')))
auth['config']=passwords
# Atomic writes and restrictive permissions.
def atomic_write(path, content):
    fd,tmp=tempfile.mkstemp(dir=str(path.parent), prefix=path.name+'.')
    with os.fdopen(fd,'w') as f: f.write(content)
    os.chmod(tmp,0o600); os.replace(tmp,path)
atomic_write(up,json.dumps(users,indent=2)+'\n')
atomic_write(cp,json.dumps(cfg,indent=2)+'\n')
PY_SYNC
  systemctl restart "$SERVICE"
}

expire_only() {
  local expired
  expired=$(python3 - <<'PY_EXPIRE'
import json, pathlib, time
up=pathlib.Path('/etc/hysteria/users.json')
if not up.exists(): print(0); raise SystemExit
users=json.loads(up.read_text()); now=time.time()
print(sum(1 for v in users.values() if isinstance(v,dict) and int(v.get('expires_at') or 0) and int(v.get('expires_at') or 0) <= now))
PY_EXPIRE
)
  if [[ "$expired" -gt 0 ]]; then
    python3 - <<'PY_EXPIRE_REMOVE'
import json, pathlib, time, os, tempfile
up=pathlib.Path('/etc/hysteria/users.json')
users=json.loads(up.read_text()); now=time.time(); before=len(users)
for name, value in list(users.items()):
    if isinstance(value,dict):
        exp=int(value.get('expires_at') or 0)
        if exp and exp <= now: del users[name]
fd,tmp=tempfile.mkstemp(dir=str(up.parent),prefix='users.json.')
with os.fdopen(fd,'w') as f: f.write(json.dumps(users,indent=2)+'\n')
os.chmod(tmp,0o600); os.replace(tmp,up)
print('Akun kedaluwarsa dihapus:',before-len(users))
PY_EXPIRE_REMOVE
    sync_auth
  fi
}

create_user() {
  local username password duration ip
  read -r -p 'Username: ' username
  [[ -n "$username" && "$username" != *[[:space:]]* ]] || { echo 'Username wajib dan tidak boleh mengandung spasi.'; return 1; }
  read -r -s -p 'Password (minimal 8 karakter): ' password; echo
  (( ${#password} >= 8 )) || { echo 'Password minimal 8 karakter.'; return 1; }
  read -r -p 'Durasi akun (hari, 0 = tanpa batas): ' duration
  [[ "$duration" =~ ^[0-9]+$ ]] || { echo 'Durasi harus angka.'; return 1; }
  read -r -p 'IP yang diizinkan (kosong jika tidak dicatat): ' ip
  USERNAME="$username" PASSWORD="$password" DURATION="$duration" ALLOWED_IP="$ip" python3 - <<'PY_ADD'
import json, os, pathlib, sys, time, ipaddress
up=pathlib.Path('/etc/hysteria/users.json')
users=json.loads(up.read_text()) if up.exists() else {}
# migrate old format
for k,v in list(users.items()):
    if isinstance(v,str): users[k]={'password':v,'expires_at':0,'allowed_ip':''}
name=os.environ['USERNAME']; password=os.environ['PASSWORD']; days=int(os.environ['DURATION']); ip=os.environ['ALLOWED_IP'].strip()
if name in users: sys.exit('Username sudah ada.')
if ip:
    try: ip=str(ipaddress.ip_address(ip))
    except ValueError: sys.exit('IP tidak valid. Masukkan satu alamat IPv4 atau IPv6.')
users[name]={'password':password,'expires_at':int(time.time()+days*86400) if days else 0,'allowed_ip':ip}
up.write_text(json.dumps(users,indent=2)+'\n'); up.chmod(0o600)
print('Akun berhasil dibuat:',name)
print('Durasi:',f'{days} hari' if days else 'tanpa batas')
print('IP dicatat:',ip or 'tidak ditentukan')
print('CATATAN: IP per akun belum bisa ditegakkan oleh auth password Hysteria bawaan; ini hanya tersimpan sebagai metadata.')
PY_ADD
  sync_auth
}

list_users() {
  python3 - <<'PY_LIST'
import json, pathlib, datetime, time
p=pathlib.Path('/etc/hysteria/users.json')
users=json.loads(p.read_text()) if p.exists() else {}
if not users: print('Belum ada akun.'); raise SystemExit
print(f"{'USERNAME':20} {'STATUS':14} {'SISA':12} {'IP TERCATAT'}")
for name,v in users.items():
    if isinstance(v,str): v={'password':v,'expires_at':0,'allowed_ip':''}
    exp=int(v.get('expires_at') or 0)
    if not exp: status='Aktif'; remain='Tanpa batas'
    elif exp<=time.time(): status='Kedaluwarsa'; remain='0 hari'
    else: status='Aktif'; remain=f"{max(1,int((exp-time.time()+86399)//86400))} hari"
    print(f"{name:20} {status:14} {remain:12} {v.get('allowed_ip') or '-'}")
print('\nPassword tidak ditampilkan. IP di atas hanya metadata, bukan pembatasan aktif per akun.')
PY_LIST
}

delete_user() {
  local username
  read -r -p 'Username yang akan dihapus: ' username
  USERNAME="$username" python3 - <<'PY_DEL'
import json, os, pathlib, sys
p=pathlib.Path('/etc/hysteria/users.json')
if not p.exists(): sys.exit('Database akun tidak ditemukan.')
u=json.loads(p.read_text()); name=os.environ['USERNAME']
if name not in u: sys.exit('Username tidak ditemukan.')
del u[name]
p.write_text(json.dumps(u,indent=2)+'\n'); p.chmod(0o600)
print('Akun dihapus:',name)
PY_DEL
  sync_auth
}

uninstall_all() {
  echo 'Ini akan menghapus service Hysteria, binary, konfigurasi, sertifikat, database akun, dan menu akun.'
  read -r -p 'Ketik HAPUS untuk melanjutkan: ' confirm
  [[ "$confirm" == HAPUS ]] || { echo 'Dibatalkan.'; return; }
  systemctl disable --now "$SERVICE" 2>/dev/null || true
  systemctl disable --now hysteria-expiry.timer 2>/dev/null || true
  rm -f /etc/systemd/system/hysteria-expiry.service /etc/systemd/system/hysteria-expiry.timer "$CRON"
  rm -f /etc/systemd/system/hysteria-server.service /etc/systemd/system/hysteria-server@.service
  rm -f "$MANAGER" /usr/local/bin/hysteria
  rm -rf /etc/hysteria
  systemctl daemon-reload
  echo 'Komponen NAMY-UDP dihapus. Aturan firewall/NAT tidak dihapus otomatis demi keamanan; periksa secara manual.'
  exit 0
}

case "${1:-menu}" in
  cleanup) expire_only; exit 0 ;;
  add) create_user; exit 0 ;;
  remove) delete_user; exit 0 ;;
  list) list_users; exit 0 ;;
  uninstall|--uninstall) uninstall_all ;;
  menu|help|--help|-h) ;;
  *) echo 'Gunakan: namyudp-user [menu|add|list|remove|cleanup|uninstall]'; exit 2 ;;
esac

while true; do
  echo
  echo '====== MANAJEMEN NAMY-UDP ======'
  echo '1. Buat akun baru'
  echo '2. Lihat akun'
  echo '3. Hapus akun'
  echo '4. Bersihkan akun kedaluwarsa'
  echo '5. Uninstall NAMY-UDP'
  echo '0. Keluar'
  read -r -p 'Pilih menu [0-5]: ' choice
  case "$choice" in
    1) create_user ;;
    2) list_users ;;
    3) delete_user ;;
    4) expire_only ;;
    5) uninstall_all ;;
    0) exit 0 ;;
    *) echo 'Pilihan tidak valid.' ;;
  esac
done
NAMYUDP_USER_MANAGER
  chmod 0750 "$USER_MANAGER_PATH"

  # Run expiration cleanup every five minutes.
  cat > /etc/systemd/system/hysteria-expiry.service <<'EXPIRY_SERVICE'
[Unit]
Description=Expire NAMY-UDP accounts
[Service]
Type=oneshot
ExecStart=/usr/local/bin/namyudp-user cleanup
EXPIRY_SERVICE
  cat > /etc/systemd/system/hysteria-expiry.timer <<'EXPIRY_TIMER'
[Unit]
Description=Run NAMY-UDP account expiry cleanup periodically
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true
[Install]
WantedBy=timers.target
EXPIRY_TIMER
  systemctl daemon-reload
  systemctl enable --now hysteria-expiry.timer
  echo 'Install menu akun ... ok'
}

configure_installation() {
  local input_domain input_port input_obfs input_password default_port
  echo
  echo '=== Konfigurasi NAMY-UDP ==='
  read -r -p "Domain yang sudah diarahkan ke IP VPS [$DOMAIN]: " input_domain
  [[ -n "$input_domain" ]] && DOMAIN="$input_domain"
  if [[ "$DOMAIN" =~ ^[0-9.]+$ ]]; then error 'Masukkan domain DNS, bukan IP.'; exit 2; fi
  default_port="${UDP_PORT#:}"
  read -r -p "Port UDP layanan [$default_port]: " input_port
  [[ -n "$input_port" ]] && default_port="$input_port"
  if [[ ! "$default_port" =~ ^[0-9]+$ ]] || (( default_port < 1 || default_port > 65535 )); then error 'Port harus angka 1-65535.'; exit 2; fi
  UDP_PORT=":$default_port"
  read -r -p "Obfs server (harus sama dengan client) [$OBFS]: " input_obfs
  [[ -n "$input_obfs" ]] && OBFS="$input_obfs"
  read -r -s -p 'Password akun awal (minimal 8 karakter): ' input_password; echo
  [[ -n "$input_password" ]] && PASSWORD="$input_password"
  if (( ${#PASSWORD} < 8 )); then error 'Password minimal 8 karakter.'; exit 2; fi
  echo "Domain: $DOMAIN"; echo "Port layanan UDP: $UDP_PORT"; echo "Obfs: $OBFS"; echo 'Password: (disembunyikan)'
  echo 'Pastikan DNS A record domain mengarah ke IP publik VPS.'; echo
}

perform_install() {
	local _is_frash_install
	if ! is_hysteria_installed; then
		_is_frash_install=1
		fi
		
                        if [[ -n "$_is_frash_install" ]]; then
                            configure_installation
                        fi
 						perform_install_hysteria_binary
						perform_install_hysteria_example_config
						perform_install_hysteria_home_legacy
						perform_install_hysteria_systemd
                        perform_install_user_manager
						setup_ssl
					    start_services
						if [[ -n "$_is_frash_install" ]]; then
							echo
							echo -e "$(tbold)Congratulation! NAMY-UDP has been successfully installed on your server.$(treset)"
							echo
							echo -e "$(tbold)Client app MB INJECTOR:$(treset)"
							echo -e "$(tblue)https://play.google.com/store/apps/details?id=com.mb.injector$(treset)"
							echo
							echo -e "Follow me!"
							echo
							echo -e "\t+ Check out my website at $(tblue)https://www.namydev.com$(treset)"
							echo -e "\t+ Follow me on Telegram: $(tblue)https://t.me/namydev$(treset)"
							echo -e "\t+ Follow me on Facebook: $(tblue)https://facebook.com/itsnamydev$(treset)"
							echo
							else
								restart_running_services
								start_services
								echo
								echo -e "$(tbold)NAMY-UDP has been successfully update to $VERSION.$(treset)"
								echo
								fi
}

perform_remove() {
	perform_remove_hysteria_binary
	stop_running_services
	perform_remove_hysteria_systemd
	
	echo
	echo -e "$(tbold)Congratulation! NAMY-UDP has been successfully removed from your server.$(treset)"
	echo
	echo -e "You still need to remove configuration files and ACME certificates manually with the following commands:"
	echo
	echo -e "\t$(tred)rm -rf "$CONFIG_DIR"$(treset)"
	if [[ "x$HYSTERIA_USER" != "xroot" ]]; then
		echo -e "\t$(tred)userdel -r "$HYSTERIA_USER"$(treset)"
		fi
		if [[ "x$FORCE_NO_SYSTEMD" != "x2" ]]; then
			echo
			echo -e "You still might need to disable all related systemd services with the following commands:"
			echo
			echo -e "\t$(tred)rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server.service$(treset)"
			echo -e "\t$(tred)rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server@*.service$(treset)"
			echo -e "\t$(tred)systemctl daemon-reload$(treset)"
			fi
			echo
}

 


setup_ssl() {
	echo "Installing ssl"

	openssl genrsa -out /etc/hysteria/hysteria.ca.key 2048

	openssl req -new -x509 -days 3650 -key /etc/hysteria/hysteria.ca.key -subj "/C=CN/ST=GD/L=SZ/O=Hysteria, Inc./CN=Hysteria Root CA" -out /etc/hysteria/hysteria.ca.crt

	openssl req -newkey rsa:2048 -nodes -keyout /etc/hysteria/hysteria.server.key -subj "/C=CN/ST=GD/L=SZ/O=Hysteria, Inc./CN=$DOMAIN" -out /etc/hysteria/hysteria.server.csr

	openssl x509 -req -extfile <(printf "subjectAltName=DNS:$DOMAIN,DNS:$DOMAIN") -days 3650 -in /etc/hysteria/hysteria.server.csr -CA /etc/hysteria/hysteria.ca.crt -CAkey /etc/hysteria/hysteria.ca.key -CAcreateserial -out /etc/hysteria/hysteria.server.crt	
 }
start_services() {
	echo "Starting NAMY-UDP"
	apt update
	sudo debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v4 boolean true"
        sudo debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v6 boolean true"
	apt -y install iptables-persistent
	iptables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport 10000:65000 -j DNAT --to-destination $UDP_PORT
	ip6tables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport 10000:65000 -j DNAT --to-destination $UDP_PORT
	sysctl net.ipv4.conf.all.rp_filter=0
	sysctl net.ipv4.conf.$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1).rp_filter=0 
	echo "net.ipv4.ip_forward = 1
	net.ipv4.conf.all.rp_filter=0
	net.ipv4.conf.$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1).rp_filter=0" > /etc/sysctl.conf  
	sysctl -p
        sudo iptables-save > /etc/iptables/rules.v4
        sudo ip6tables-save > /etc/iptables/rules.v6
	systemctl enable hysteria-server.service
	systemctl start hysteria-server.service	
}



main() {
parse_arguments "$@"
	check_permission
	check_environment
	check_hysteria_user "hysteria"
	check_hysteria_homedir "/var/lib/$HYSTERIA_USER"
	case "$OPERATION" in
	"install")
	perform_install
	;;
	"remove")
	perform_remove
	;;
	 
	*)
	error "Unknown operation '$OPERATION'."
	;;
	esac
}

main "$@"

# vim:set ft=bash ts=2 sw=2 sts=2 et:
