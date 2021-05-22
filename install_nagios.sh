#!/bin/bash

set -e
RED="\033[1;31m"
GREEN="\033[1;32m"
NC="\033[0m"
CURRENT_DIR_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${CURRENT_DIR_PATH}/$(basename "${BASH_SOURCE[0]}")"
SELF_NAME=$(basename "$0")
INSTALL_NAGIOS=0
CONFIGURE_REMOTE_SERVER=0

INSTALL_DIR="/tmp/install_nagios"
NAGIOS_URL="https://github.com/NagiosEnterprises/nagioscore/archive"
NAGIOS_PAKAGE="nagios-4.4.4.tar.gz"
NAGIOS_PLUGINS_URL="https://nagios-plugins.org/download"
NAGIOS_PLUGINS_PACKAGE="nagios-plugins-2.2.1.tar.gz"
DEFAULT_PASSWD="test"
CHECK_NRPE_URL="https://github.com/NagiosEnterprises/nrpe/releases/download/nrpe-3.2.1"
CHECK_NRPE_PACKAGE="nrpe-3.2.1.tar.gz"
EMAIL="julia0615.jb@gmail.com"


VERBOSITY=1


error(){
    if [[ "${VERBOSITY}" -gt 0 ]]; then
        echo -e "${RED}[ERROR] $1${NC}"; exit 1
    fi
}

info(){
    if [[ "${VERBOSITY}" -gt 0 ]]; then
        echo -e "${GREEN}[INFO] $1${NC}"
    fi
}

cmd(){
   local cmd="${1}"
   eval "${cmd}"
   if [[ $? -gt 0 ]]; then
        error "${cmd} execution failed"
   else
       info "${cmd} execution succeed"
   fi
}


USAGE(){
    cat << EOF

${SELF_NAME} [-v] [-q] [-h] [-n] [-r]- script that automate installing Nagios and Nagios plugins

Where:
    -v  set needed version of kernel version
    -n  install Nagios with all needed plugins
    -r  install Nagios deamon on remote devices 
    -h  show this help message
    -q  quiet mode, doesnt print any info/error messages

    example:
        ${SELF_NAME} -v 4.19.81-OpenNetworkLinux

EOF
}

check_std_out(){
    local success_m="${1}"
    local fail_m="${2}"
    if [[ $? -eq 0 ]]; then
        info "+ ${success_m}"
    else
        error "- ${fail_m}"
    fi
}

while getopts ":xhqvnr" opt; do
    case ${opt} in
        x) set -x ;;
        h) USAGE; exit 0 ;;
        q) VERBOSITY=0 ;;
        n) INSTALL_NAGIOS=1 ;;
        r) CONFIGURE_REMOTE_SERVER=1 ;;
        :)
            USAGE >&2; error "Option -$OPTARG requires an argument." >&2 ;;
        *)
            USAGE
            error "Provided option not found" >&2 ;;

    esac
done

if [[ $# -eq 0 ]]; then
    error "No arguments supplied"
fi


cmd_in_install_dir() {
    local path=${1}
    local cmd="${2}"
    echo "$cmd"
    ( cd "${path}" ; info "($(pwd)) ${cmd}" && eval "${cmd}")
}

update_system() {
    info "Prepare invironment"
    cmd "sudo apt update"
    cmd "sudo apt install autoconf gcc make unzip libgd-dev libmcrypt-dev libssl-dev dc snmp libnet-snmp-perl gettext -y"
}

install_nagios() {
    info "Installing Nagios"
    if [[ ! -f "${INSTALL_DIR}/${NAGIOS_PAKAGE}" ]]; then
        cmd_in_install_dir "${INSTALL_DIR}" "curl -LO ${NAGIOS_URL}/${NAGIOS_PAKAGE}"
    fi
    cmd_in_install_dir "${INSTALL_DIR}" "tar zfx ${NAGIOS_PAKAGE}"
    cmd_in_install_dir "${INSTALL_DIR}/nagioscore-nagios-4.4.4" "./configure --with-httpd-conf=/etc/apache2/sites-enabled"
    cmd_in_install_dir "${INSTALL_DIR}/nagioscore-nagios-4.4.4" "make all"
    cmd_in_install_dir "${INSTALL_DIR}/nagioscore-nagios-4.4.4" "sudo make install-groups-users"
    cmd_in_install_dir "${INSTALL_DIR}/nagioscore-nagios-4.4.4" "sudo make install"
    cmd_in_install_dir "${INSTALL_DIR}/nagioscore-nagios-4.4.4" "sudo make install-daemoninit"
    cmd_in_install_dir "${INSTALL_DIR}/nagioscore-nagios-4.4.4" "sudo make install-commandmode"
    cmd_in_install_dir "${INSTALL_DIR}/nagioscore-nagios-4.4.4" "sudo make install-config"
    cmd_in_install_dir "${INSTALL_DIR}/nagioscore-nagios-4.4.4" "sudo make install-webconf"
    cmd "sudo a2enmod rewrite"
    cmd "sudo a2enmod cgi"
    cmd "sudo usermod -a -G nagios www-data"
    cmd "sudo usermod -a -G nagios www-data"
    cmd "echo '${DEFAULT_PASSWD}' | sudo htpasswd -i -c /usr/local/nagios/etc/htpasswd.users nagiosadmin"
    cmd "sudo systemctl restart apache2"
}

install_plugins() {
    info "Install Plugins"
    if [[ ! -f "${INSTALL_DIR}/${NAGIOS_PLUGINS_PACKAGE}" ]]; then
        cmd_in_install_dir "${INSTALL_DIR}" "curl -LO ${NAGIOS_PLUGINS_URL}/${NAGIOS_PLUGINS_PACKAGE}"
    
        cmd_in_install_dir "${INSTALL_DIR}" "tar zfx ${NAGIOS_PLUGINS_PACKAGE}"
        cmd_in_install_dir "${INSTALL_DIR}/nagios-plugins-2.2.1" "./configure"
        cmd_in_install_dir "${INSTALL_DIR}/nagios-plugins-2.2.1" "make"
        cmd_in_install_dir "${INSTALL_DIR}/nagios-plugins-2.2.1" "sudo make install"
    else 
        info "Skip Installing Plugins"
    fi
}

install_check_nrpe() {
    info "Installing check_nrpe"
    if [[ ! -f "${INSTALL_DIR}/${CHECK_NRPE_PACKAGE}" ]]; then
        cmd_in_install_dir "${INSTALL_DIR}" "curl -LO ${CHECK_NRPE_URL}/${CHECK_NRPE_PACKAGE}"
        cmd_in_install_dir "${INSTALL_DIR}" "tar zfx ${CHECK_NRPE_PACKAGE}"
        cmd_in_install_dir "${INSTALL_DIR}/nrpe-3.2.1" "./configure"
        cmd_in_install_dir "${INSTALL_DIR}/nrpe-3.2.1" "make check_nrpe"
        cmd_in_install_dir "${INSTALL_DIR}/nrpe-3.2.1" "sudo make install-plugin"
    fi
}

basic_nagios_configuration() {
    info "Basic Nagios Configuration"
    # Configuring Nagios
    cmd " sudo sed -i '/^#cfg_dir=.*servers/s/^#//' /usr/local/nagios/etc/nagios.cfg"
    if [[ ! -d /usr/local/nagios/etc/servers ]]; then
        cmd "sudo mkdir -p /usr/local/nagios/etc/servers"
    fi
    # set email
    cmd "sudo sed -i 's/nagios@localhost/${EMAIL}/' /usr/local/nagios/etc/objects/contacts.cfg"
    
    if [[ -z $(grep "check_nrpe" /usr/local/nagios/etc/objects/commands.cfg) ]]; then
        info "Configure check_nrpe command"
        sudo cat check_nrpe.config >> /usr/local/nagios/etc/objects/commands.cfg
    fi

    info "check_nrpe command configured"
    cmd "sudo systemctl start nagios"
}

nagios_info() {
    info "=============== Summary ==============="
    info "Nagios succsessfully installed"
    info "Login: nagiosadmin"
    info "Password: test"
}

install_check_nrpe_deamon() {
    info "Installing check_nrpe"
    if [[ ! -f "${INSTALL_DIR}/${CHECK_NRPE_PACKAGE}" ]]; then
        cmd_in_install_dir "${INSTALL_DIR}" "curl -LO ${CHECK_NRPE_URL}/${CHECK_NRPE_PACKAGE}"
        cmd_in_install_dir "${INSTALL_DIR}" "tar zfx ${CHECK_NRPE_PACKAGE}"
        cmd_in_install_dir "${INSTALL_DIR}/nrpe-3.2.1" "./configure"
        cmd_in_install_dir "${INSTALL_DIR}/nrpe-3.2.1" "sudo make install-daemon"
        cmd_in_install_dir "${INSTALL_DIR}/nrpe-3.2.1" "sudo make install-config"
        cmd_in_install_dir "${INSTALL_DIR}/nrpe-3.2.1" "sudo make install-init"
    else 
        info "Skip Installing check_nrpe"
    fi
}


main() {
    # Update system
    if [[ ! -d ${INSTALL_DIR} ]]; then
        info "Creating install dir"
        cmd "mkdir -p ${INSTALL_DIR}"
    fi
    if [[ ${INSTALL_NAGIOS} -eq 1 ]]; then
        update_system
        # Install Nagios
        install_nagios
        # Install Plugins for Nagios
        install_plugins
        install_check_nrpe
        basic_nagios_configuration
        nagios_info
    fi
    # Installing the check_nrpe Plugin
    if [[ ${CONFIGURE_REMOTE_SERVER} -eq 1 ]]; then
        cmd "sudo useradd nagios"
        update_system
        # Install Plugins for Nagios
        install_plugins
        install_check_nrpe_deamon
    fi
}

main