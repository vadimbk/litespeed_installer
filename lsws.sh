#!/bin/bash

# Configuration - Edit these values or use command line parameters
ADMINUSER='admin'
ADMINPASSWORD=''
EMAIL=''
HTTPPORT=80
HTTPSPORT=443
NOWEBPOPRTS=0          # Web ports will be installed by default
LSPHPVER=''           # No PHP by default - user must specify
ADMINPORT=7080
LICENSE='TRIAL'
USER=''
GROUP=''
SITEDOMAIN=''
PHPINSTALL='basic'    # basic installation by default
PHPPACKAGES=''        # Custom PHP packages list
HOSTNAME=''           # Hostname for SSL certificate

ONLY_SSL=0            # Only SSL generation flag

# Default PHP packages for full installation
DEFAULT_PHP_PACKAGES_CENTOS="common gd process mbstring mysqlnd xml pdo"
DEFAULT_PHP_PACKAGES_DEBIAN="common curl gd mbstring mysql xml pdo"
DEFAULT_PHP_PACKAGES_EXTRA_NEW="imap"
DEFAULT_PHP_PACKAGES_EXTRA_OLD="imap json"

# System variables
CMDFD='/opt'
LS_VER=''  # Will be determined automatically
OSNAMEVER=UNKNOWN
OSNAME=
OSVER=
OSTYPE=$(uname -m)
SERVER_ROOT=/usr/local/lsws
WEBCF="$SERVER_ROOT/conf/httpd_config.xml"
PWD_FILE=$SERVER_ROOT/password
CONFFILE=myssl.xml
CSR=example.csr
KEY=example.key
CERT=example.crt
APT='apt-get -qq'
YUM='yum -q'
ALLERRORS=0
TESTGETERROR=no
LSPHPVERLIST=(74 80 81 82 83 84)
ACTION=INSTALL
FORCEYES=0
VERBOSE=0
FPACE='      '

function usage
{
    echo -e "\033[1mOPTIONS\033[0m"
    echo "  -L,    --license                    To use specified LSWS serial number."    
    echo "  --adminuser [USERNAME]              To set the WebAdmin username for LiteSpeed instead of admin."
    echo "  -A,    --adminpassword [PASSWORD]   To set the WebAdmin password for LiteSpeed instead of using a random one."
    echo "  --adminport [PORTNUMBER]            To set the WebAdmin console port number instead of 7080."
    echo "  -E,    --email [EMAIL]              To set the administrator email."
    echo "  --lsphp [VERSION]                   To set the LSPHP version, such as 83. We currently support versions '${LSPHPVERLIST[@]}'."
    echo "  --phpinstall [basic|full]           To set PHP installation type: basic (lsphp only) or full (with extensions). Default is basic."
    echo "  --phppackages [PACKAGES]            To set custom PHP packages list (space-separated), e.g. 'common mysql gd mbstring'."
    echo "  --user [USERNAME]                   To set the user that LiteSpeed will run as. Default is www-data."
    echo "  --group [GROUPNAME]                 To set the group that LiteSpeed will run as. Default is www-data."
    echo "  --httpport [PORTNUMBER]             To set the HTTP port number instead of 80."
    echo "  --httpsport [PORTNUMBER]            To set the HTTPS port number instead of 443."
    echo "  --nowebports                        To disable HTTP and HTTPS listeners (only admin access)."
    echo "  --hostname [DOMAIN]                 To set hostname for Let's Encrypt SSL certificate generation."
    echo "  --only-ssl                          To only generate/renew SSL certificate (requires existing LiteSpeed installation)."
    echo "  -U,    --uninstall                  To uninstall LiteSpeed and remove installation directory."
    echo "  -Q,    --quiet                      To use quiet mode, won't prompt to input anything."
    echo "  -V,    --version                    To display LiteSpeed Enterprise current version and OS."
    echo "  -v,    --verbose                    To display more messages during the installation."
    echo "  -H,    --help                       To display help messages."
    echo 
    echo -e "\033[1mEXAMPLES\033[0m"
    echo "  ./lsws2.sh                          To install LiteSpeed with default settings."
    echo "  ./lsws2.sh --lsphp 83               To install LiteSpeed with lsphp83."
    echo "  ./lsws2.sh --hostname example.com   To install LiteSpeed with Let's Encrypt SSL for example.com."
    echo "  ./lsws2.sh --hostname example.com --only-ssl  To only generate/renew SSL certificate."
    echo "  ./lsws2.sh --phpinstall basic       To install LiteSpeed with basic PHP (interpreter only)."
    echo "  ./lsws2.sh --phppackages 'common mysql gd'  To install LiteSpeed with custom PHP packages."
    echo "  ./lsws2.sh -A 123456 -E a@cc.com    To install LiteSpeed with WebAdmin password \"123456\" and email a@cc.com."
    echo "  ./lsws2.sh --user nobody --group nobody  To install LiteSpeed running as nobody:nobody."
    echo
    exit 0
}

function display_license
{
    echo '**********************************************************************************************'
    echo '*                    LiteSpeed Enterprise Simple Installation Script                         *'
    echo '**********************************************************************************************'
}

function check_value_follow
{
    FOLLOWPARAM=$1
    local PARAM=$1
    local KEYWORD=$2

    if [ "$1" = "-n" ] || [ "$1" = "-e" ] || [ "$1" = "-E" ] ; then
        FOLLOWPARAM=
    else
        local PARAMCHAR=$(echo $1 | awk '{print substr($0,1,1)}')
        if [ "$PARAMCHAR" = "-" ] ; then
            FOLLOWPARAM=
        fi
    fi

    if [ -z "$FOLLOWPARAM" ] ; then
        if [ ! -z "$KEYWORD" ] ; then
            echo "Error: '$PARAM' is not a valid '$KEYWORD', please check and try again."
            usage
        fi
    fi
}

function check_root
{
    local INST_USER=`id -u`
    if [ $INST_USER != 0 ] ; then
        echo "Sorry, only the root user can install."
        exit 1
    fi
}

function check_hostname_availability
{
    if [ -z "$HOSTNAME" ]; then
        return 0
    fi
    
    echo "${FPACE} - Checking hostname availability: $HOSTNAME"
    
    # First check if dig is available
    if command -v dig >/dev/null 2>&1; then
        # Use dig for DNS resolution
        local HOSTNAME_IP=$(dig +short $HOSTNAME 2>/dev/null | head -1)
    elif command -v nslookup >/dev/null 2>&1; then
        # Fallback to nslookup
        local HOSTNAME_IP=$(nslookup $HOSTNAME 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
    elif command -v host >/dev/null 2>&1; then
        # Fallback to host command
        local HOSTNAME_IP=$(host $HOSTNAME 2>/dev/null | grep "has address" | awk '{print $4}' | head -1)
    else
        # Last resort - try ping (may not work on all systems)
        local HOSTNAME_IP=$(ping -c 1 $HOSTNAME 2>/dev/null | grep -oP '(?<=\()[0-9.]+(?=\))' | head -1)
    fi
    
    if [ -z "$HOSTNAME_IP" ]; then
        echo "${FPACE} - ERROR: Hostname $HOSTNAME does not resolve to any IP"
        echo "${FPACE} - Please check your DNS settings"
        if [ "$FORCEYES" != "1" ] ; then
            printf 'Continue anyway? [y/N] '
            read answer
            if [ "$answer" != "Y" ] && [ "$answer" != "y" ] ; then
                echo "Installation aborted!"
                exit 0
            fi
        fi
        return 1
    fi
    
    echo "${FPACE} - Hostname resolves to: $HOSTNAME_IP"
    
    # Try to determine server's external IP (optional check)
    echo "${FPACE} - Attempting to determine server's external IP..."
    local SERVER_IP=""
    
    # Attempt 1: via Amazon (fast and reliable)
    SERVER_IP=$(timeout 5 curl -s http://checkip.amazonaws.com 2>/dev/null)
    
    # Attempt 2: via ipinfo.io
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(timeout 5 curl -s http://ipinfo.io/ip 2>/dev/null)
    fi
    
    # Attempt 3: via httpbin (another popular service)
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(timeout 5 curl -s http://httpbin.org/ip | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' 2>/dev/null)
    fi
    
    if [ -n "$SERVER_IP" ]; then
        echo "${FPACE} - Server external IP detected: $SERVER_IP"
        
        # Compare IP addresses
        if [ "$SERVER_IP" = "$HOSTNAME_IP" ]; then
            echo "${FPACE} - ✓ Perfect! Hostname points directly to this server"
        else
            echo "${FPACE} - ⚠ Notice: Hostname points to $HOSTNAME_IP, but server IP is $SERVER_IP"
            echo "${FPACE} - This might be OK if you're using CDN, load balancer, or proxy"
            echo "${FPACE} - Let's Encrypt will test actual connectivity during certificate generation"
        fi
    else
        echo "${FPACE} - Could not determine server's external IP (offline or network issue)"
        echo "${FPACE} - This is not critical - proceeding with hostname check only"
    fi
    
    return 0
}

function check_hostname_http_connectivity
{
    if [ -z "$HOSTNAME" ]; then
        return 0
    fi
    
    echo "${FPACE} - Testing HTTP connectivity to $HOSTNAME on port 80..."
    
    # Test if port 80 is accessible on the domain
    if timeout 10 bash -c "echo >/dev/tcp/$HOSTNAME/80" 2>/dev/null; then
        echo "${FPACE} - ✓ Port 80 is accessible on $HOSTNAME"
        return 0
    else
        echo "${FPACE} - ⚠ Port 80 may not be accessible on $HOSTNAME"
        echo "${FPACE} - This could affect HTTP-01 challenge for Let's Encrypt"
        if [ "$FORCEYES" != "1" ] ; then
            printf 'Continue with SSL certificate generation? [y/N] '
            read answer
            if [ "$answer" != "Y" ] && [ "$answer" != "y" ] ; then
                echo "Skipping SSL certificate generation"
                return 1
            fi
        fi
        return 1
    fi
}

function install_certbot
{
    echo "${FPACE} - Installing Certbot for Let's Encrypt"
    
    if [ "$OSNAME" = "centos" ] ; then
        # Install EPEL first for CentOS
        ${YUM} -y install epel-release >/dev/null 2>&1
        ${YUM} -y install certbot >/dev/null 2>&1
    else
        # For Debian/Ubuntu
        ${APT} update >/dev/null 2>&1
        ${APT} -y install certbot >/dev/null 2>&1
    fi
    
    if [ $? != 0 ] ; then
        echo "An error occurred during Certbot installation."
        ALLERRORS=1
        return 1
    fi
    
    echo "${FPACE} - Certbot installed successfully"
}

function generate_letsencrypt_certificate
{
    if [ -z "$HOSTNAME" ]; then
        echo "${FPACE} - No hostname specified, skipping SSL certificate generation"
        return 0
    fi
    
    echo "${FPACE} - Generating Let's Encrypt SSL certificate for $HOSTNAME"
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        install_certbot
        if [ $? != 0 ]; then
            return 1
        fi
    fi
    
    # Set email for Let's Encrypt if not provided
    local LE_EMAIL="$EMAIL"
    if [ -z "$LE_EMAIL" ]; then
        LE_EMAIL="admin@$HOSTNAME"
    fi
    
    local CERT_COMMAND=""
    local DOMAIN_PARAM="-d $HOSTNAME"
    
    echo "${FPACE} - Generating certificate for $HOSTNAME using standalone method"
    
    # Use standalone method - temporarily stop LiteSpeed
    echo "${FPACE} - Stopping LiteSpeed temporarily for certificate generation"
    
    # Stop LiteSpeed properly
    systemctl stop lsws >/dev/null 2>&1
    ${SERVER_ROOT}/bin/lswsctrl stop >/dev/null 2>&1
    sleep 2
    
    # Kill any remaining processes on port 80
    fuser -k 80/tcp >/dev/null 2>&1
    
    CERT_COMMAND="certbot certonly --standalone --agree-tos --non-interactive --email $LE_EMAIL $DOMAIN_PARAM"
    echo "${FPACE} - Running standalone certificate generation"
    $CERT_COMMAND
    local CERT_RESULT=$?
    
    echo "${FPACE} - Restarting LiteSpeed"
    systemctl start lsws >/dev/null 2>&1
    sleep 3
    
    # Ensure LiteSpeed is running
    if ! systemctl is-active --quiet lsws; then
        ${SERVER_ROOT}/bin/lswsctrl start >/dev/null 2>&1
    fi
    
    if [ $CERT_RESULT != 0 ]; then
        echo "${FPACE} - Certificate generation failed"
        echo "${FPACE} - You may need to:"
        echo "${FPACE}   1. Ensure $HOSTNAME points to this server"
        echo "${FPACE}   2. Check firewall settings (ports 80 and 443)"
        echo "${FPACE}   3. Verify domain DNS is correctly configured"
        ALLERRORS=1
        return 1
    fi
    
    # Verify certificate was created
    if [ -f "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$HOSTNAME/privkey.pem" ]; then
        echo "${FPACE} - SSL certificate generated successfully"
        
        # Update certificate paths in configuration
        update_ssl_config_with_letsencrypt
        
        # Update renewal configuration for standalone method
        echo "${FPACE} - Updating renewal configuration for standalone method"
        update_renewal_config
        
        # Always force graceful restart after SSL config update
        echo "${FPACE} - Performing graceful restart to apply SSL configuration"
        ${SERVER_ROOT}/bin/lswsctrl restart >/dev/null 2>&1
        sleep 5
        
        # Verify SSL configuration is active
        if openssl s_client -connect localhost:$HTTPSPORT -servername $HOSTNAME </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
            echo "${FPACE} - SSL certificate successfully applied to HTTPS listener"
        fi
        
        if openssl s_client -connect localhost:$ADMINPORT -servername $HOSTNAME </dev/null 2>/dev/null | grep -q "subject"; then
            echo "${FPACE} - SSL certificate successfully applied to Admin listener"
        fi
        
        return 0
    else
        echo "${FPACE} - Certificate files not found after generation"
        ALLERRORS=1
        return 1
    fi
}

function update_renewal_config
{
    local RENEWAL_CONFIG="/etc/letsencrypt/renewal/$HOSTNAME.conf"
    
    if [ -f "$RENEWAL_CONFIG" ]; then
        echo "${FPACE} - Updating renewal configuration for standalone method"
        
        # Backup renewal config
        cp "$RENEWAL_CONFIG" "$RENEWAL_CONFIG.backup.$(date +%s)" 2>/dev/null
        
        # Set standalone authenticator
        sed -i '/authenticator = /c\authenticator = standalone' "$RENEWAL_CONFIG"
        sed -i '/installer = /c\installer = None' "$RENEWAL_CONFIG"
        
        # Remove webroot-specific settings
        sed -i '/webroot_path = /d' "$RENEWAL_CONFIG"
        sed -i '/\[\[webroot_map\]\]/,$d' "$RENEWAL_CONFIG"
        
        echo "${FPACE} - Renewal configuration updated to use standalone method"
    else
        echo "${FPACE} - Renewal configuration file not found: $RENEWAL_CONFIG"
    fi
}

function update_ssl_config_with_letsencrypt
{
    if [ ! -f "$WEBCF" ]; then
        echo "${FPACE} - LiteSpeed configuration not found, skipping SSL config update"
        return 1
    fi

    echo "${FPACE} - Updating LiteSpeed SSL configuration with Let's Encrypt certificates"

    # Set Let's Encrypt certificate paths
    local LE_CERT_PATH="/etc/letsencrypt/live/$HOSTNAME/fullchain.pem"
    local LE_KEY_PATH="/etc/letsencrypt/live/$HOSTNAME/privkey.pem"

    # Update main server HTTPS listener
    sed -i "s|<keyFile>.*</keyFile>|<keyFile>$LE_KEY_PATH</keyFile>|g" "$WEBCF"
    sed -i "s|<certFile>.*</certFile>|<certFile>$LE_CERT_PATH</certFile>|g" "$WEBCF"

    # Update admin panel SSL
    local ADMIN_CONFIG="$SERVER_ROOT/admin/conf/admin_config.xml"
    if [ -f "$ADMIN_CONFIG" ]; then
        sed -i 's|<secure>0</secure>|<secure>1</secure>|g' "$ADMIN_CONFIG"
        if ! grep -q "<keyFile>" "$ADMIN_CONFIG"; then
            sed -i '/<secure>1<\/secure>/a\            <keyFile>'"$LE_KEY_PATH"'</keyFile>\n            <certFile>'"$LE_CERT_PATH"'</certFile>' "$ADMIN_CONFIG"
        else
            sed -i "s|<keyFile>.*</keyFile>|<keyFile>$LE_KEY_PATH</keyFile>|g" "$ADMIN_CONFIG"
            sed -i "s|<certFile>.*</certFile>|<certFile>$LE_CERT_PATH</certFile>|g" "$ADMIN_CONFIG"
        fi
    fi
}

function setup_certbot_auto_renewal
{
    if [ -z "$HOSTNAME" ]; then
        echo "${FPACE} - No hostname specified, skipping auto-renewal setup"
        return 0
    fi

    echo "${FPACE} - Setting up automatic certificate renewal (standalone method)"

    # Fix renewal config to use standalone method
    local RENEWAL_CONFIG="/etc/letsencrypt/renewal/$HOSTNAME.conf"
    if [ -f "$RENEWAL_CONFIG" ]; then
        echo "${FPACE} - Updating renewal config for standalone method"
        cp "$RENEWAL_CONFIG" "$RENEWAL_CONFIG.backup.$(date +%s)"
        sed -i '/authenticator = /c\authenticator = standalone' "$RENEWAL_CONFIG"
        sed -i '/installer = /c\installer = None' "$RENEWAL_CONFIG"
        sed -i '/webroot_path = /d' "$RENEWAL_CONFIG"
        sed -i '/\[\[webroot_map\]\]/,$d' "$RENEWAL_CONFIG"
    fi

    # Setup cron job for ALL systems
    echo "${FPACE} - Configuring cron job for certificate renewal"
    local CRON_FILE="/etc/cron.d/certbot"
    
    # Stop systemd timer if it exists to avoid conflicts
    if systemctl list-unit-files 2>/dev/null | grep -q "certbot.timer"; then
        echo "${FPACE} - Disabling systemd timer to use cron instead"
        systemctl stop certbot.timer >/dev/null 2>&1
        systemctl disable certbot.timer >/dev/null 2>&1
    fi
    
    # Create cron job with robust stop/start commands
    if [ -f "$CRON_FILE" ]; then
        cp "$CRON_FILE" "$CRON_FILE.backup.$(date +%s)"
    fi
    
    cat > "$CRON_FILE" << 'EOF'
# Let's Encrypt certificate renewal for LiteSpeed
# Runs twice daily with random delay
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Renew certificates with complete LiteSpeed stop/start
0 */12 * * * root /usr/bin/test -x /usr/bin/certbot && perl -e 'sleep int(rand(43200))' && /usr/bin/certbot -q renew --pre-hook "systemctl stop lsws; /usr/local/lsws/bin/lswsctrl stop; killall -9 litespeed; fuser -k 80/tcp; sleep 3" --post-hook "/usr/local/lsws/bin/lswsctrl start; systemctl start lsws; sleep 5"
EOF
    
    chmod 644 "$CRON_FILE"

    echo "${FPACE} - Auto-renewal configured with robust stop/start commands"
    echo "${FPACE} - Manual renewal: certbot renew --pre-hook 'systemctl stop lsws; /usr/local/lsws/bin/lswsctrl stop; killall -9 litespeed; fuser -k 80/tcp; sleep 3' --post-hook '/usr/local/lsws/bin/lswsctrl start; systemctl start lsws; sleep 5'"
}

function update_system()
{
    echo 'System update'
    if [ "$OSNAME" = "centos" ] ; then
        ${YUM} update -y >/dev/null 2>&1
    else
        disable_needrestart
        ${APT} update && ${APT} upgrade -y >/dev/null 2>&1
    fi
}

function check_wget
{
    which wget  >/dev/null 2>&1
    if [ $? != 0 ] ; then
        if [ "$OSNAME" = "centos" ] ; then
            ${YUM} -y install wget
        else
            ${APT} -y install wget
        fi

        which wget  >/dev/null 2>&1
        if [ $? != 0 ] ; then
            echo "An error occured during wget installation."
            ALLERRORS=1
        fi
    fi
}

function check_curl
{
    which curl  >/dev/null 2>&1
    if [ $? != 0 ] ; then
        if [ "$OSNAME" = "centos" ] ; then
            ${YUM} -y install curl
        else
            ${APT} -y install curl
        fi

        which curl  >/dev/null 2>&1
        if [ $? != 0 ] ; then
            echo "An error occured during curl installation."
            ALLERRORS=1
        fi
    fi
}

function check_tar
{
    which tar >/dev/null 2>&1
    if [ $? != 0 ] ; then
        echo "Installing tar..."
        if [ "$OSNAME" = "centos" ] ; then
            ${YUM} -y install tar
        else
            ${APT} -y install tar
        fi

        which tar >/dev/null 2>&1
        if [ $? != 0 ] ; then
            echo "An error occurred during tar installation."
            ALLERRORS=1
        fi
    fi
}

function install_centos_dependencies
{
    if [ "$OSNAME" = "centos" ]; then
        echo "Installing CentOS dependencies for LiteSpeed..."

        # Install required libraries for LiteSpeed
        ${YUM} -y install libxcrypt-compat glibc libatomic >/dev/null 2>&1

        # For CentOS 10 - install additional compatibility libraries
        if [ "$OSVER" = "10" ]; then
            echo "Installing CentOS 10 compatibility libraries..."
            ${YUM} -y install compat-libcrypt1 libcrypt1 >/dev/null 2>&1 || true

            # Create symlink if libcrypt.so.1 is missing
            if [ ! -f /lib64/libcrypt.so.1 ] && [ -f /lib64/libcrypt.so.2 ]; then
                echo "Creating libcrypt.so.1 compatibility symlink..."
                ln -sf /lib64/libcrypt.so.2 /lib64/libcrypt.so.1
            fi
        fi

        echo "CentOS dependencies installed"
    fi
}

function install_dns_tools
{
    echo "${FPACE} - Installing DNS tools"
    if [ "$OSNAME" = "centos" ] ; then
        # For CentOS - install bind-utils which provides dig, nslookup, host
        ${YUM} -y install bind-utils >/dev/null 2>&1
        
        # Verify dig is installed
        if ! command -v dig >/dev/null 2>&1; then
            echo "${FPACE} - Warning: dig not available, DNS check may not work properly"
        fi
    else
        # For Debian/Ubuntu - install dnsutils
        ${APT} -y install dnsutils >/dev/null 2>&1
    fi
}

function restart_lsws
{
    systemctl stop lsws >/dev/null 2>&1
    systemctl start lsws
}

function get_latest_lsws_version
{
    echo "Detecting latest LiteSpeed version..."
    
    # Method 1: Try to get version from release log page (most reliable)
    LS_VER=$(curl -s --max-time 10 'https://www.litespeedtech.com/products/litespeed-web-server/release-log' | \
             grep -oP 'LSWS\s+\K[0-9]+\.[0-9]+\.[0-9]+(?=\(.*?Stable)' | \
             head -1)
    
    # Method 2: Try packages directory if first method fails
    if [ -z "$LS_VER" ]; then
        LS_VER=$(curl -s --max-time 10 'https://www.litespeedtech.com/packages/6.0/' | \
                 grep -oP 'lsws-\K[0-9]+\.[0-9]+\.[0-9]+(?=-ent)' | \
                 sort -V | tail -1)
    fi
    
    # Fallback to known stable version if all detection methods fail
    if [ -z "$LS_VER" ]; then
        LS_VER='6.3.3'
    fi
    
    echo "LiteSpeed version: $LS_VER"
}

function check_os
{
    if [ -f /etc/centos-release ] ; then
        OSNAME=centos
        case $(cat /etc/centos-release | tr -dc '0-9.'|cut -d \. -f1) in 
        7)
            OSNAMEVER=CENTOS7
            OSVER=7
            ;;
        8)
            OSNAMEVER=CENTOS8
            OSVER=8
            ;;
        9)
            OSNAMEVER=CENTOS9
            OSVER=9
            ;;
        *)
            OSNAMEVER=CENTOS
            OSVER=$(cat /etc/centos-release | tr -dc '0-9.'|cut -d \. -f1)
            ;;            
        esac
    elif [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        case $(cat /etc/redhat-release | tr -dc '0-9.'|cut -d \. -f1) in 
        7)
            OSNAMEVER=CENTOS7
            OSVER=7
            ;;
        8)
            OSNAMEVER=CENTOS8
            OSVER=8
            ;;
        9)
            OSNAMEVER=CENTOS9
            OSVER=9
            ;;
        *)
            OSNAMEVER=CENTOS
            OSVER=$(cat /etc/redhat-release | tr -dc '0-9.'|cut -d \. -f1)
            ;;            
        esac             
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu
        case $(cat /etc/os-release | grep UBUNTU_CODENAME | cut -d = -f 2) in
        bionic)
            OSNAMEVER=UBUNTU18
            OSVER=bionic
            ;;
        focal)            
            OSNAMEVER=UBUNTU20
            OSVER=focal
            ;;
        jammy)            
            OSNAMEVER=UBUNTU22
            OSVER=jammy
            ;;          
        noble)            
            OSNAMEVER=UBUNTU24
            OSVER=noble
            ;;
        *)
            OSNAMEVER=UBUNTU
            OSVER=$(cat /etc/os-release | grep VERSION_ID | cut -d '"' -f 2)
            ;;                
        esac
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
        USER='nobody'
        GROUP='nogroup'
        case $(cat /etc/os-release | grep VERSION_CODENAME | cut -d = -f 2) in
        stretch) 
            OSNAMEVER=DEBIAN9
            OSVER=stretch
            ;;
        buster)
            OSNAMEVER=DEBIAN10
            OSVER=buster
            ;;
        bullseye)
            OSNAMEVER=DEBIAN11
            OSVER=bullseye
            ;;
        bookworm)
            OSNAMEVER=DEBIAN12
            OSVER=bookworm
            ;;
        *)
            OSNAMEVER=DEBIAN
            OSVER=$(cat /etc/debian_version)
            ;;            
        esac    
    fi

    if [ "$OSNAMEVER" = '' ] || [ "$OSNAMEVER" = 'UNKNOWN' ] ; then
        echo "Sorry, currently one click installation only supports Centos(7-9), Debian(10-12) and Ubuntu(18,20,22,24)."
        exit 1
    else
        if [ "$OSNAME" = "centos" ] ; then
            echo "Current platform is $OSNAME $OSVER."
        else
            export DEBIAN_FRONTEND=noninteractive
            echo "Current platform is $OSNAMEVER $OSNAME $OSVER."
        fi
    fi
}

function update_email
{
    if [ "$EMAIL" = '' ] ; then
        if [ -n "$HOSTNAME" ]; then
            EMAIL="admin@$HOSTNAME"
        elif [ "$SITEDOMAIN" = "*" ] || [ "$SITEDOMAIN" = '' ] ; then
            EMAIL=root@localhost
        else
            EMAIL=root@$SITEDOMAIN
        fi
    fi
}

function random_password
{
    if [ ! -z ${1} ]; then 
        TEMPPASSWORD="${1}"
    else    
        TEMPPASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
    fi
}

function main_gen_password
{
    if [ "$ADMINPASSWORD" = '' ]; then
        random_password
        ADMINPASSWORD="${TEMPPASSWORD}"
    fi
}

function update_centos_hashlib
{
    if [ "$OSNAME" = 'centos' ] ; then
        ${YUM} -y install python-hashlib >/dev/null 2>&1
    fi
}

function get_memory
{
    RAM_KB=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
}

function check_memory
{
    if [ "${OSNAMEVER}" = 'CENTOS9' ]; then
        get_memory
        if [ "$RAM_KB" -lt "1800000" ]; then
            echo 'remi package needs at least 2GB RAM to install it. Exit!'
            exit 1
        fi
    fi
}

function KILL_PROCESS
{
    PROC_NUM=$(pidof ${1})
    if [ ${?} = 0 ]; then
        kill -9 ${PROC_NUM}
    fi
}

function install_lsws
{
    cd ${CMDFD}/
    if [ -e ${CMDFD}/lsws* ] || [ -d ${SERVER_ROOT} ]; then
        echo 'Remove existing LSWS'
        systemctl stop lsws >/dev/null 2>&1
        KILL_PROCESS litespeed
        rm -rf ${CMDFD}/lsws*
        rm -rf ${SERVER_ROOT}
    fi
    
    # Detect architecture
    ARCH=$(uname -m)
    echo "Detected architecture: $ARCH"
    
    # Set correct package based on architecture
    if [ "$ARCH" = "x86_64" ]; then
        PACKAGE_ARCH="x86_64"
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        PACKAGE_ARCH="aarch64"
    else
        echo "Unsupported architecture: $ARCH"
        echo "LiteSpeed Enterprise supports x86_64 and aarch64 only"
        ALLERRORS=1
        return 1
    fi
    
    echo "Download LiteSpeed Web Server for $PACKAGE_ARCH"
    DOWNLOAD_URL="https://www.litespeedtech.com/packages/6.0/lsws-${LS_VER}-ent-${PACKAGE_ARCH}-linux.tar.gz"
    echo "Downloading from: $DOWNLOAD_URL"
    
    wget --no-check-certificate "$DOWNLOAD_URL" -P ${CMDFD}/
    if [ $? != 0 ]; then
        echo "Failed to download LiteSpeed package for $PACKAGE_ARCH"
        echo "Trying x86_64 version as fallback..."
        wget --no-check-certificate "https://www.litespeedtech.com/packages/6.0/lsws-${LS_VER}-ent-x86_64-linux.tar.gz" -P ${CMDFD}/
        if [ $? != 0 ]; then
            echo "Failed to download any LiteSpeed package"
            ALLERRORS=1
            return 1
        fi
    fi
    
    echo 'Extract LiteSpeed package'
    tar -zxf lsws-*-ent-*-linux.tar.gz
    if [ $? != 0 ]; then
        echo "Failed to extract LiteSpeed package"
        ALLERRORS=1
        return 1
    fi
    
    rm -f lsws-*.tar.gz
    
    # Find the extracted directory
    LSWS_DIR=$(find . -maxdepth 1 -name "lsws-*" -type d | head -1)
    if [ -z "$LSWS_DIR" ]; then
        echo "Failed to find extracted LiteSpeed directory"
        ALLERRORS=1
        return 1
    fi
    
    cd "$LSWS_DIR"
    
    if [ "${LICENSE}" == 'TRIAL' ]; then 
        echo 'Download trial license'
        wget --no-check-certificate http://license.litespeedtech.com/reseller/trial.key
        if [ $? != 0 ]; then
            echo "Failed to download trial license"
            ALLERRORS=1
            return 1
        fi
    else 
        echo "${LICENSE}" > serial.no
    fi    
    
    # Check if install.sh exists
    if [ ! -f "install.sh" ]; then
        echo "install.sh not found in LiteSpeed package"
        ALLERRORS=1
        return 1
    fi
    
    echo 'Prepare installation scripts'
    sed -i '/^license$/d' install.sh
    sed -i 's/read TMPS/TMPS=0/g' install.sh
    sed -i 's/read TMP_YN/TMP_YN=N/g' install.sh
    sed -i '/read [A-Z]/d' functions.sh
    sed -i 's/HTTP_PORT=$TMP_PORT/HTTP_PORT=8088/g' functions.sh
    sed -i 's/ADMIN_PORT=$TMP_PORT/ADMIN_PORT=7080/g' functions.sh
    sed -i 's/$TMP_PORT -eq $HTTP_PORT/$ADMIN_PORT -eq $HTTP_PORT/g' functions.sh
    sed -i "/^license()/i\
    PASS_ONE=${ADMINPASSWORD}\
    PASS_TWO=${ADMINPASSWORD}\
    TMP_USER=${USER}\
    TMP_GROUP=${GROUP}\
    TMP_PORT=''\
    TMP_DEST=''\
    ADMIN_USER=${ADMINUSER}\
    ADMIN_EMAIL=${EMAIL}\
    " functions.sh

    echo 'Install LiteSpeed Web Server'
    chmod +x install.sh
    ./install.sh
    INSTALL_RESULT=$?
    
    if [ $INSTALL_RESULT != 0 ]; then
        echo "LiteSpeed installation failed with exit code: $INSTALL_RESULT"
        ALLERRORS=1
        return 1
    fi
    
    # Check if installation was successful
    if [ ! -d "${SERVER_ROOT}" ]; then
        echo "LiteSpeed installation failed - SERVER_ROOT directory not created"
        ALLERRORS=1
        return 1
    fi
    
    if [ -f ${SERVER_ROOT}/bin/lswsctrl ]; then
        ${SERVER_ROOT}/bin/lswsctrl start >/dev/null 2>&1
    fi
    
    if [ -f ${SERVER_ROOT}/VERSION ]; then
        SERVERV=$(cat ${SERVER_ROOT}/VERSION)
        echo "Version: lsws ${SERVERV}"
    else
        echo "Warning: VERSION file not found"
    fi
    
    cd ${CMDFD}
    rm -rf lsws-*
    cd /
}

function install_lsws_centos
{
    local action=install
    if [ "$1" = "Update" ] ; then
        action=update
    elif [ "$1" = "Reinstall" ] ; then
        action=reinstall
    fi

    if [ "${OSNAMEVER}" = 'CENTOS9' ]; then
        echo "${FPACE} - add remi repo"
    else
        echo "${FPACE} - add epel repo"
        ${YUM} -y $action epel-release >/dev/null 2>&1
    fi
    echo "${FPACE} - add litespeedtech repo"
    wget -q -O - https://repo.litespeed.sh | bash >/dev/null 2>&1

    if [ ! -e $SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp ] ; then
        action=install
    fi
    echo "${FPACE} - Install lsphp$LSPHPVER"
    if [ "$action" = "reinstall" ] ; then
        ${YUM} -y remove lsphp$LSPHPVER-mysqlnd >/dev/null 2>&1
    fi
    
    # Basic installation - just the PHP interpreter
    if [ "$PHPINSTALL" = "basic" ]; then
        ${YUM} -y install lsphp$LSPHPVER >/dev/null 2>&1
    else
        # Full installation with extensions
        local PACKAGES_TO_INSTALL="lsphp$LSPHPVER"
        
        # Use custom packages if specified, otherwise use defaults
        if [ -n "$PHPPACKAGES" ]; then
            echo "${FPACE} - Installing custom PHP packages: $PHPPACKAGES"
            for pkg in $PHPPACKAGES; do
                PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL lsphp$LSPHPVER-$pkg"
            done
        else
            echo "${FPACE} - Installing default PHP packages"
            for pkg in $DEFAULT_PHP_PACKAGES_CENTOS; do
                PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL lsphp$LSPHPVER-$pkg"
            done
            
            # Add version-specific packages
            if [[ "$LSPHPVER" =~ (81|82|83|84) ]]; then
                for pkg in $DEFAULT_PHP_PACKAGES_EXTRA_NEW; do
                    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL lsphp$LSPHPVER-$pkg"
                done
            elif [[ "$LSPHPVER" == 7* ]]; then
                PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL lsphp$LSPHPVER-mcrypt"
                for pkg in $DEFAULT_PHP_PACKAGES_EXTRA_OLD; do
                    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL lsphp$LSPHPVER-$pkg"
                done
            fi
        fi
        
        echo "${FPACE} - Installing: $PACKAGES_TO_INSTALL"
        ${YUM} -y install $PACKAGES_TO_INSTALL >/dev/null 2>&1
    fi
    
    # Check if LSPHP installed correctly
    if [ ! -d "$SERVER_ROOT/lsphp$LSPHPVER" ]; then
        echo "${FPACE} - LSPHP directory not created, reinstalling..."
        ${YUM} -y remove --purge lsphp$LSPHPVER* >/dev/null 2>&1
        ${YUM} -y install lsphp$LSPHPVER lsphp$LSPHPVER-common >/dev/null 2>&1
        
        # Force reconfigure if still not working
        if [ ! -d "$SERVER_ROOT/lsphp$LSPHPVER" ]; then
            echo "${FPACE} - Force configure lsphp$LSPHPVER"
            rpm --force --nodeps -i $(yum list --downloadonly lsphp$LSPHPVER 2>/dev/null | grep lsphp$LSPHPVER | head -1 | awk '{print $1}') >/dev/null 2>&1
        fi
    fi
    
    if [ $? != 0 ] ; then
        echo "An error occured during LiteSpeed installation."
        ALLERRORS=1        
    fi
}

function install_lsws_debian
{
    local action=
    if [ "$1" = "Update" ] ; then
        action="--only-upgrade"
    elif [ "$1" = "Reinstall" ] ; then
        action="--reinstall"
    fi
    echo "${FPACE} - add litespeedtech repo"
    wget -q -O - https://repo.litespeed.sh | bash >/dev/null 2>&1
    echo "${FPACE} - update list"
    ${APT} -y update >/dev/null 2>&1

    if [ ${?} != 0 ] ; then
        echo "An error occured during repository update."
        ALLERRORS=1
    fi
    
    if [ ! -e $SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp ] ; then
        action=
    fi
    
    echo "${FPACE} - Install lsphp$LSPHPVER"
    
    # Determine correct MySQL package name based on distribution
    local MYSQL_PKG=""
    if [ "$OSNAME" = "ubuntu" ]; then
        # Ubuntu uses mysql for most versions
        MYSQL_PKG="lsphp$LSPHPVER-mysql"
    elif [ "$OSNAME" = "debian" ]; then
        # Debian uses mysql for most versions
        MYSQL_PKG="lsphp$LSPHPVER-mysql"
    fi
    
    # Basic installation - just the PHP interpreter
    if [ "$PHPINSTALL" = "basic" ]; then
        ${APT} -y install $action lsphp$LSPHPVER >/dev/null 2>&1
    else
        # Full installation with extensions
        local PACKAGES_TO_INSTALL="lsphp$LSPHPVER"
        
        # Use custom packages if specified, otherwise use defaults
        if [ -n "$PHPPACKAGES" ]; then
            echo "${FPACE} - Installing custom PHP packages: $PHPPACKAGES"
            for pkg in $PHPPACKAGES; do
                PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL lsphp$LSPHPVER-$pkg"
            done
        else
            echo "${FPACE} - Installing default PHP packages"
            for pkg in $DEFAULT_PHP_PACKAGES_DEBIAN; do
                PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL lsphp$LSPHPVER-$pkg"
            done
            
            # Add version-specific packages
            if [[ "$LSPHPVER" =~ (81|82|83|84) ]]; then
                for pkg in $DEFAULT_PHP_PACKAGES_EXTRA_NEW; do
                    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL lsphp$LSPHPVER-$pkg"
                done
            elif [[ "$LSPHPVER" == 7* ]]; then
                for pkg in $DEFAULT_PHP_PACKAGES_EXTRA_OLD; do
                    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL lsphp$LSPHPVER-$pkg"
                done
            fi
        fi
        
        echo "${FPACE} - Installing: $PACKAGES_TO_INSTALL"
        ${APT} -y install $action $PACKAGES_TO_INSTALL >/dev/null 2>&1
    fi

    # Check if LSPHP installed correctly
    if [ ! -d "$SERVER_ROOT/lsphp$LSPHPVER" ]; then
        echo "${FPACE} - LSPHP directory not created, attempting manual installation..."
        
        # Force clean installation
        ${APT} -y remove --purge lsphp$LSPHPVER* >/dev/null 2>&1
        ${APT} -y autoremove >/dev/null 2>&1
        ${APT} -y autoclean >/dev/null 2>&1
        
        # Update package cache
        ${APT} -y update >/dev/null 2>&1
        
        # Try installing just the base package first
        echo "${FPACE} - Installing base lsphp$LSPHPVER package"
        ${APT} -y install lsphp$LSPHPVER >/dev/null 2>&1
        
        if [ ! -d "$SERVER_ROOT/lsphp$LSPHPVER" ]; then
            echo "${FPACE} - Force configure lsphp$LSPHPVER"
            dpkg --configure -a >/dev/null 2>&1
            ${APT} -y install --reinstall lsphp$LSPHPVER >/dev/null 2>&1
        fi
        
        # Last resort - create directory manually and link to system PHP
        if [ ! -d "$SERVER_ROOT/lsphp$LSPHPVER" ]; then
            echo "${FPACE} - Creating LSPHP directory manually"
            mkdir -p "$SERVER_ROOT/lsphp$LSPHPVER/bin/"
            
            # Try to find appropriate PHP binary based on version
            local PHP_MAJOR="${LSPHPVER:0:1}"
            local PHP_MINOR="${LSPHPVER:1:1}"
            local PHP_VERSION="$PHP_MAJOR.$PHP_MINOR"
            
            if [ -f "/usr/bin/php$PHP_VERSION" ]; then
                ln -sf "/usr/bin/php$PHP_VERSION" "$SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp"
                echo "${FPACE} - Linked to /usr/bin/php$PHP_VERSION"
            elif [ -f "/usr/bin/php" ]; then
                SYSTEM_PHP_VERSION=$(php -v 2>/dev/null | head -n 1 | cut -d " " -f 2 | cut -f1-2 -d".")
                if [[ "$SYSTEM_PHP_VERSION" == "$PHP_VERSION" ]]; then
                    ln -sf "/usr/bin/php" "$SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp"
                    echo "${FPACE} - Linked to /usr/bin/php (version $SYSTEM_PHP_VERSION)"
                else
                    echo "${FPACE} - WARNING: Found PHP $SYSTEM_PHP_VERSION, but requested $PHP_VERSION"
                    ln -sf "/usr/bin/php" "$SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp"
                    echo "${FPACE} - Linked anyway to /usr/bin/php"
                fi
            else
                echo "${FPACE} - ERROR: No suitable PHP binary found"
                ALLERRORS=1
            fi
        fi
    fi

    # Final verification
    if [ ! -f "$SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp" ]; then
        echo "An error occured during lsphp$LSPHPVER installation."
        ALLERRORS=1
    else
        echo "${FPACE} - LSPHP$LSPHPVER installed successfully"
    fi
}

function install_litespeed
{
    echo "Start setup LiteSpeed"
    local STATUS=Install
    install_lsws
    
    # Only install PHP if version is specified
    if [ -n "$LSPHPVER" ]; then
        echo "Installing PHP version: $LSPHPVER"
        if [ "$OSNAME" = "centos" ] ; then
            install_lsws_centos $STATUS
        else
            install_lsws_debian $STATUS
        fi
        
        # Final check and fix for LSPHP installation
        if [ ! -f "$SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp" ]; then
            echo "${FPACE} - LSPHP not properly installed, attempting manual fix..."
            
            # Remove broken installation
            if [ "$OSNAME" = "centos" ] ; then
                ${YUM} -y remove lsphp$LSPHPVER* >/dev/null 2>&1
                ${YUM} -y install lsphp$LSPHPVER lsphp$LSPHPVER-common >/dev/null 2>&1
            else
                ${APT} -y remove --purge lsphp$LSPHPVER* >/dev/null 2>&1
                ${APT} -y autoremove >/dev/null 2>&1
                ${APT} -y install lsphp$LSPHPVER lsphp$LSPHPVER-common >/dev/null 2>&1
            fi
            
            # If still not working, create manually
            if [ ! -f "$SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp" ]; then
                echo "${FPACE} - Creating LSPHP structure manually"
                mkdir -p "$SERVER_ROOT/lsphp$LSPHPVER/bin/"
                
                # Find system PHP and create symlink
                local PHP_MAJOR="${LSPHPVER:0:1}"
                local PHP_MINOR="${LSPHPVER:1:1}"
                local PHP_VERSION="$PHP_MAJOR.$PHP_MINOR"
                
                if [ -f "/usr/bin/php$PHP_VERSION" ]; then
                    ln -sf "/usr/bin/php$PHP_VERSION" "$SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp"
                    echo "${FPACE} - Linked to /usr/bin/php$PHP_VERSION"
                elif [ -f "/usr/bin/php" ]; then
                    ln -sf "/usr/bin/php" "$SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp"
                    echo "${FPACE} - Linked to /usr/bin/php"
                else
                    echo "${FPACE} - ERROR: No suitable PHP binary found"
                    ALLERRORS=1
                fi
                
                # Set proper permissions
                if [ -f "$SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp" ]; then
                    chmod +x "$SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp"
                    chown -R ${USER}:${GROUP} "$SERVER_ROOT/lsphp$LSPHPVER/"
                    echo "${FPACE} - LSPHP manually configured successfully"
                fi
            fi
        else
            echo "${FPACE} - LSPHP$LSPHPVER installed successfully"
        fi
        
        killall -9 lsphp >/dev/null 2>&1
    else
        echo "No PHP version specified - skipping PHP installation"
        echo "Use --lsphp [version] to install PHP (available versions: ${LSPHPVERLIST[@]})"
    fi
    
    echo "End setup LiteSpeed"
}

function disable_needrestart
{
    if [ -d /etc/needrestart/conf.d ]; then
        echo 'List Restart services only'
        cat >> /etc/needrestart/conf.d/disable.conf <<END
# Restart services (l)ist only, (i)nteractive or (a)utomatically. 
\$nrconf{restart} = 'l'; 
# Disable hints on pending kernel upgrades. 
\$nrconf{kernelhints} = 0;         
END
    fi
}

function gen_selfsigned_cert
{
    if [ -e $CONFFILE ] ; then
        source $CONFFILE 2>/dev/null
        if [ $? != 0 ]; then
            . $CONFFILE
        fi
    fi

    SSL_COUNTRY="${SSL_COUNTRY:-US}"
    SSL_STATE="${SSL_STATE:-New Jersey}"
    SSL_LOCALITY="${SSL_LOCALITY:-Virtual}"
    SSL_ORG="${SSL_ORG:-LiteSpeedCommunity}"
    SSL_ORGUNIT="${SSL_ORGUNIT:-Testing}"
    SSL_HOSTNAME="${SSL_HOSTNAME:-webadmin}"
    SSL_EMAIL="${SSL_EMAIL:-$EMAIL}"
    COMMNAME=$(hostname)
    
    cat << EOF > $CSR
[req]
prompt=no
distinguished_name=litespeed
[litespeed]
commonName = ${COMMNAME}
countryName = ${SSL_COUNTRY}
localityName = ${SSL_LOCALITY}
organizationName = ${SSL_ORG}
organizationalUnitName = ${SSL_ORGUNIT}
stateOrProvinceName = ${SSL_STATE}
emailAddress = ${SSL_EMAIL}
name = litespeed
initials = CP
dnQualifier = litespeed
[server_exts]
extendedKeyUsage=1.3.6.1.5.5.7.3.1
EOF
    openssl req -x509 -config $CSR -extensions 'server_exts' -nodes -days 820 -newkey rsa:2048 -keyout ${KEY} -out ${CERT} >/dev/null 2>&1
    rm -f $CSR
    
    mv ${KEY}   $SERVER_ROOT/conf/$KEY
    mv ${CERT}  $SERVER_ROOT/conf/$CERT
    chmod 0600 $SERVER_ROOT/conf/$KEY
    chmod 0600 $SERVER_ROOT/conf/$CERT
}

function set_lsws_password
{
    if [ -f "$SERVER_ROOT/admin/fcgi-bin/admin_php5" ]; then
        ENCRYPT_PASS=`"$SERVER_ROOT/admin/fcgi-bin/admin_php5" -q "$SERVER_ROOT/admin/misc/htpasswd.php" $ADMINPASSWORD`
    elif [ -f "$SERVER_ROOT/admin/fcgi-bin/admin_php" ]; then
        ENCRYPT_PASS=`"$SERVER_ROOT/admin/fcgi-bin/admin_php" -q "$SERVER_ROOT/admin/misc/htpasswd.php" $ADMINPASSWORD`
    else
        echo "Warning: admin_php not found, trying alternative method"
        ENCRYPT_PASS=$(openssl passwd -apr1 $ADMINPASSWORD)
    fi
    
    if [ -n "$ENCRYPT_PASS" ] ; then
        echo "${ADMINUSER}:$ENCRYPT_PASS" > "$SERVER_ROOT/admin/conf/htpasswd"
        if [ $? = 0 ] ; then
            echo "Set LiteSpeed Web Admin access."
        else
            echo "LiteSpeed WebAdmin password not changed."
        fi
    else
        echo "Failed to encrypt password"
    fi
}

function config_server()
{
    echo "${FPACE} - Config LiteSpeed"
    if [ -e "${WEBCF}" ] ; then
        echo "${FPACE} - Check existing port"
        grep "<address.*:${HTTPPORT}<\|${HTTPSPORT}<"  ${WEBCF} >/dev/null 2>&1
        if [ ${?} = 0 ]; then
            echo "Detect port ${HTTPPORT} || ${HTTPSPORT}, will skip domain setup!"
        else
            # Only create HTTP/HTTPS listeners if --nowebports is not set
            if [ "$NOWEBPORTS" != "1" ]; then
                echo "${FPACE} - Create HTTP/HTTPS listener"

                # Determine certificate files to use
                local CERT_FILE="$SERVER_ROOT/conf/$CERT"
                local KEY_FILE="$SERVER_ROOT/conf/$KEY"

                # If hostname is set and Let's Encrypt certificates exist, use them
                if [ -n "$HOSTNAME" ] && [ -f "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" ]; then
                    CERT_FILE="$SERVER_ROOT/conf/cert.pem"
                    KEY_FILE="$SERVER_ROOT/conf/key.pem"
                fi

                sed -i "/<listenerList>/a \\
    <listener> \\
      <name>HTTP</name> \\
      <address>*:"${HTTPPORT}"</address> \\
      <secure>0</secure> \\
      <vhostMapList> \\
      </vhostMapList> \\
    </listener> \\
    <listener> \\
      <name>HTTPS</name> \\
      <address>*:"${HTTPSPORT}"</address> \\
      <secure>1</secure> \\
      <vhostMapList> \\
      </vhostMapList> \\
      <keyFile>${KEY_FILE}</keyFile> \\
      <certFile>${CERT_FILE}</certFile> \\
    </listener>" "${WEBCF}"
            else
                echo "${FPACE} - Skipping HTTP/HTTPS listeners (--nowebports enabled)"
            fi
        fi
        
        # Only setup PHP external app if PHP version is specified
        if [ -n "$LSPHPVER" ]; then
            echo "${FPACE} - Setup PHP external App"
            sed -i "/<\/security>/a \\
  <extProcessorList> \\
    <extProcessor> \\
      <type>lsapi</type> \\
      <name>lsphp"${LSPHPVER}"</name> \\
      <address>uds://tmp/lshttpd/lsphp"${LSPHPVER}".sock</address> \\
      <maxConns>200</maxConns> \\
      <env>PHP_LSAPI_CHILDREN=200</env> \\
      <env>LSAPI_AVOID_FORK=1</env> \\
      <initTimeout>60</initTimeout> \\
      <retryTimeout>0</retryTimeout> \\
      <persistConn>1</persistConn> \\
      <respBuffer>0</respBuffer> \\
      <autoStart>3</autoStart> \\
      <path>${SERVER_ROOT}/lsphp"${LSPHPVER}"/bin/lsphp</path> \\
      <backlog>100</backlog> \\
      <instances>1</instances> \\
      <priority>0</priority> \\
      <memSoftLimit></memSoftLimit> \\
      <memHardLimit></memHardLimit> \\
      <procSoftLimit></procSoftLimit> \\
      <procHardLimit></procHardLimit> \\
    </extProcessor> \\
  </extProcessorList> \\
  <scriptHandlerList> \\
    <scriptHandler> \\
      <suffix>php</suffix> \\
      <type>lsapi</type> \\
      <handler>lsphp"${LSPHPVER}"</handler> \\
    </scriptHandler> \\
  </scriptHandlerList> \\
  <cache> \\
    <cacheEngine>7</cacheEngine> \\
    <storage> \\
      <cacheStorePath>/home/lscache/</cacheStorePath> \\
    </storage> \\
  </cache>" "${WEBCF}"
            
            # Create symlink for PHP binary if it doesn't exist
            if [ ! -f /bin/php ]; then
                ln -s ${SERVER_ROOT}/lsphp"${LSPHPVER}"/bin/php /bin/php
            fi
        fi
        
        sed -i -e "s/<adminEmails>root@localhost/<adminEmails>$EMAIL/g" "${WEBCF}"
        sed -i -e 's/<allowOverride>0</<allowOverride>31</g' "${WEBCF}"
    else
        echo "${WEBCF} is missing. It appears that something went wrong during LiteSpeed installation."
        ALLERRORS=1
    fi

    if [ ${ADMINPORT} != 7080 ]; then
        config_admin_port
    fi
}

function config_admin_port
{
    echo 'Start updating web admin port number'
    if [ -e ${SERVER_ROOT}/admin/conf/admin_config.xml ]; then 
        sed -i "s/7080/${ADMINPORT}/g" ${SERVER_ROOT}/admin/conf/admin_config.xml
    else
        echo "${SERVER_ROOT}/admin/conf/admin_config.xml is not found, skip!"
    fi        
}

function change_owner
{
    chown -R ${USER}:${GROUP} ${1}
}

function after_install_display
{
    chmod 600 "${PWD_FILE}"
    if [ "$ALLERRORS" = "0" ] ; then
        echo "Congratulations! Installation finished."
        
        if [ -n "$HOSTNAME" ]; then
            echo ""
            echo "SSL Certificate Information:"
            if [ -f "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" ]; then
                echo "Let's Encrypt SSL certificate generated for: $HOSTNAME"
                echo "Certificate auto-renewal is configured"
                echo "Certificate expires: $(openssl x509 -noout -enddate -in /etc/letsencrypt/live/$HOSTNAME/cert.pem | cut -d= -f2)"
            else
                echo "Self-signed certificate generated"
                echo "Consider generating Let's Encrypt certificate manually if needed"
            fi
        fi
    else
        echo "Installation finished. Some errors seem to have occured, please check this as you may need to manually fix them."
    fi
    echo 'End LiteSpeed one click installation << << << << << << <<'
    echo
}

function befor_install_display
{
    echo
    echo "Starting to install LiteSpeed to $SERVER_ROOT/ with the parameters below,"
    
    # Determine external IP for console URL
    local CONSOLE_IP="$HOSTNAME"
    if [ -z "$CONSOLE_IP" ]; then
        CONSOLE_IP=$(curl -s --max-time 5 http://checkip.amazonaws.com 2>/dev/null || echo "YOUR-SERVER-IP")
    fi
    
    echo "WebAdmin Console URL:     https://$CONSOLE_IP:$ADMINPORT"
    echo "WebAdmin username:        $ADMINUSER"
    echo "WebAdmin password:        $ADMINPASSWORD"
    echo "WebAdmin email:           $EMAIL"
    
    # Display license information
    if [ "$LICENSE" = "TRIAL" ]; then
        echo "License:                  15-day TRIAL"
    else
        echo "License:                  $LICENSE"
    fi
    
    if [ -n "$LSPHPVER" ]; then
        echo "LSPHP version:            $LSPHPVER"
        echo "PHP installation:         $PHPINSTALL"
        if [ -n "$PHPPACKAGES" ]; then
            echo "Custom PHP packages:      $PHPPACKAGES"
        fi
    else
        echo "LSPHP version:            Not installed (use --lsphp [version] to install)"
    fi
    
    if [ -n "$HOSTNAME" ]; then
        echo "SSL Hostname:             $HOSTNAME"
        echo "SSL Type:                 Standard Let's Encrypt certificate"
    else
        echo "SSL Certificate:          Self-signed (use --hostname for Let's Encrypt)"
    fi
    if [ "$NOWEBPORTS" = "1" ]; then
        echo "Web ports:                Disabled (admin access only)"
    else
        echo "Server HTTP port:         $HTTPPORT"
        echo "Server HTTPS port:        $HTTPSPORT"
    fi
    echo "Admin port:               $ADMINPORT"    
    
    # Show actual user:group that will be used with system info
    echo "Server user:group:        $USER:$GROUP"
    if [ "$OSNAME" = "centos" ]; then
        echo "                          (CentOS default: nobody:nobody for security)"
    fi
    
    echo "Your password will be written to file:  ${PWD_FILE}"
    echo 
    
    if [ "$FORCEYES" != "1" ] ; then
        printf 'Are these settings correct? Type n to quit, otherwise will continue. [Y/n]  '
        read answer
        if [ "$answer" = "N" ] || [ "$answer" = "n" ] ; then
            echo "Installation aborted!"
            exit 0
        fi
    fi
    echo 'Start LiteSpeed one click installation >> >> >> >> >> >> >>'
}

function main_lsws_password
{
    echo "WebAdmin username is [$ADMINUSER], password is [$ADMINPASSWORD]." >> ${PWD_FILE}
    set_lsws_password
}

function uninstall_warn
{
    if [ "$FORCEYES" != "1" ] ; then
        echo
        printf "\033[31mAre you sure you want to uninstall? Type 'Y' to continue, otherwise will quit.[y/N]\033[0m "
        read answer
        echo

        if [ "$answer" != "Y" ] && [ "$answer" != "y" ] ; then
            echo "Uninstallation aborted!"
            exit 0
        fi
        echo 
    fi
    echo 'Start LiteSpeed uninstallation >> >> >> >> >> >> >>'
}

function uninstall_lsws_debian
{
    echo "${FPACE} - Uninstall LiteSpeed"
    rm -rf $SERVER_ROOT/
    if [ $? != 0 ] ; then
        echo "An error occured while uninstalling LiteSpeed."
        ALLERRORS=1
    fi 
}

function uninstall_php_debian
{
    echo "${FPACE} - Uninstall LSPHP"
    ${APT} -y --purge remove lsphp* >/dev/null 2>&1
    if [ -e /usr/bin/php ] && [ -L /usr/bin/php ]; then 
        rm -f /usr/bin/php
    fi
}

function uninstall_lsws_centos
{
    echo "${FPACE} - Remove LiteSpeed"
    rm -rf $SERVER_ROOT/
    if [ $? != 0 ] ; then
        echo "An error occured while uninstalling LiteSpeed."
        ALLERRORS=1
    fi 
}

function uninstall_php_centos
{
    ls "${SERVER_ROOT}" | grep lsphp >/dev/null
    if [ $? = 0 ] ; then
        local LSPHPSTR="$(ls ${SERVER_ROOT} | grep -i lsphp | tr '\n' ' ')"
        for LSPHPVER in ${LSPHPSTR}; do 
            echo "${FPACE} - Detect LSPHP version $LSPHPVER"
            if [ "$LSPHPVER" = "lsphp80" ]; then
                ${YUM} -y remove lsphp$LSPHPVER lsphp$LSPHPVER-common lsphp$LSPHPVER-gd lsphp$LSPHPVER-process lsphp$LSPHPVER-mbstring \
                lsphp$LSPHPVER-mysqlnd lsphp$LSPHPVER-xml  lsphp$LSPHPVER-pdo lsphp$LSPHPVER-imap lsphp* >/dev/null 2>&1
            else
                ${YUM} -y remove lsphp$LSPHPVER lsphp$LSPHPVER-common lsphp$LSPHPVER-gd lsphp$LSPHPVER-process lsphp$LSPHPVER-mbstring \
                lsphp$LSPHPVER-mysqlnd lsphp$LSPHPVER-xml lsphp$LSPHPVER-mcrypt lsphp$LSPHPVER-pdo lsphp$LSPHPVER-imap lsphp$LSPHPVER-json lsphp* >/dev/null 2>&1
            fi                
            if [ $? != 0 ] ; then
                echo "An error occured while uninstalling lsphp$LSPHPVER"
                ALLERRORS=1
            fi
        done 
    else
        echo "${FPACE} - Uninstall LSPHP"
        ${YUM} -y remove lsphp* >/dev/null 2>&1
        echo "Uninstallation cannot get the currently installed LSPHP version."
        echo "May not uninstall LSPHP correctly."
        LSPHPVER=
    fi
}

function uninstall
{
    echo "Stopping LiteSpeed services..."
    systemctl stop lshttpd >/dev/null 2>&1
    systemctl disable lshttpd >/dev/null 2>&1
    
    echo "Removing LiteSpeed files..."
    if [ "$OSNAME" = "centos" ] ; then
        uninstall_lsws_centos
        uninstall_php_centos
    else
        uninstall_lsws_debian
        uninstall_php_debian
    fi
    
    rm -f /etc/systemd/system/lshttpd.service
    systemctl daemon-reload
    
    # Clean up SSL certificates and renewal jobs
    echo "Cleaning up SSL certificates and renewal jobs..."
    if [ -d "/etc/letsencrypt" ]; then
        echo "Let's Encrypt certificates found. Use 'certbot delete' to remove them manually if needed."
    fi
    
    # Remove custom renewal timer if it exists
    if [ -f "/etc/systemd/system/certbot-renewal.timer" ]; then
        systemctl stop certbot-renewal.timer >/dev/null 2>&1
        systemctl disable certbot-renewal.timer >/dev/null 2>&1
        rm -f /etc/systemd/system/certbot-renewal.timer
        rm -f /etc/systemd/system/certbot-renewal.service
        systemctl daemon-reload
    fi
    
    # Remove custom cron job if it exists
    if [ -f "/etc/cron.d/certbot-renewal" ]; then
        rm -f /etc/cron.d/certbot-renewal
    fi
    
    echo "LiteSpeed uninstalled successfully."
}

function uninstall_result
{
    if [ "$ALLERRORS" != "0" ] ; then
        echo "Some error(s) occured during uninstallation. Please check manually."
    fi
    echo 'End LiteSpeed uninstallation << << << << << << <<'
}

function test_page
{
    local URL=$1
    local KEYWORD=$2
    local PAGENAME=$3
    curl -skL  $URL | grep -i "$KEYWORD" >/dev/null 2>&1
    if [ $? != 0 ] ; then
        echo "Error: $PAGENAME failed."
        TESTGETERROR=yes
    else
        echo "OK: $PAGENAME passed."
    fi
}

function test_lsws_admin
{
    test_page https://localhost:${ADMINPORT}/ "LiteSpeed WebAdmin" "test webAdmin page"
}

function test_lsws
{
    # Only test web ports if they are enabled
    if [ "$NOWEBPORTS" != "1" ]; then
        test_page http://localhost:$HTTPPORT/  LiteSpeed "test Example HTTP vhost page"
        test_page https://localhost:$HTTPSPORT/  LiteSpeed "test Example HTTPS vhost page"
    else
        echo "Skipping web port tests (--nowebports enabled)"
    fi

    # Test SSL certificate if hostname is configured
    if [ -n "$HOSTNAME" ]; then
        echo "Testing SSL certificate for $HOSTNAME..."
        if [ -f "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" ]; then
            # Test Let's Encrypt certificate
            openssl x509 -noout -text -in "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" | grep -q "CN.*$HOSTNAME"
            if [ $? = 0 ]; then
                echo "OK: Let's Encrypt SSL certificate is valid for $HOSTNAME"
            else
                echo "Warning: SSL certificate may not be properly configured for $HOSTNAME"
            fi
        fi
    fi
}

function main_lsws_test
{
    echo "Start auto testing >> >> >> >>"
    test_lsws_admin
    test_lsws

    if [ "${TESTGETERROR}" = "yes" ] ; then
        echo "Errors were encountered during testing. In many cases these errors can be solved manually by referring to installation logs."
        echo "Service loading issues can sometimes be resolved by performing a restart of the web server."
        echo "Reinstalling the web server can also help if neither of the above approaches resolve the issue."
    fi

    echo "End auto testing << << << <<"
    echo 'Thanks for using LiteSpeed One click installation!'
    echo
}

function check_existing_installation
{
    if [ -d "$SERVER_ROOT" ] && [ -f "$SERVER_ROOT/bin/lswsctrl" ]; then
        echo "Existing LiteSpeed installation detected at $SERVER_ROOT"
        return 0
    else
        echo "No existing LiteSpeed installation found"
        return 1
    fi
}

function ssl_only_mode
{
    echo "SSL-only mode: Generating/renewing SSL certificate for existing LiteSpeed installation"
    
    if ! check_existing_installation; then
        echo "Error: No existing LiteSpeed installation found. Cannot proceed with SSL-only mode."
        echo "Please install LiteSpeed first without --only-ssl flag."
        exit 1
    fi
    
    # Validate parameters
    if [ -z "$HOSTNAME" ]; then
        echo "Error: --hostname parameter is required for SSL certificate generation."
        echo "Usage: $0 --hostname your-domain.com --only-ssl"
        exit 1
    fi
    
    echo "Checking hostname availability..."
    check_hostname_availability
    
    echo "Installing DNS tools..."
    install_dns_tools
    
    echo "Generating Let's Encrypt certificate..."
    generate_letsencrypt_certificate
    
    if [ $? = 0 ]; then
        echo "Setting up certificate auto-renewal..."
        setup_certbot_auto_renewal
        
        echo "Restarting LiteSpeed to apply new certificates..."
        restart_lsws
        
        echo "SSL certificate setup completed successfully!"
        echo "Standard certificate generated for $HOSTNAME"
        
        # Display certificate information
        if [ -f "/etc/letsencrypt/live/$HOSTNAME/cert.pem" ]; then
            echo "Certificate expires: $(openssl x509 -noout -enddate -in /etc/letsencrypt/live/$HOSTNAME/cert.pem | cut -d= -f2)"
        fi
    else
        echo "SSL certificate generation failed. Please check the errors above."
        exit 1
    fi
    
    exit 0
}

function main_init_check
{
    check_root
    get_latest_lsws_version
    check_os
    check_memory
}

function main_init_package
{
    update_centos_hashlib
    update_system
    check_wget
    check_curl
    check_tar
    install_centos_dependencies
    install_dns_tools
}

function action_uninstall
{
    if [ "$ACTION" = "UNINSTALL" ] ; then
        uninstall_warn
        uninstall
        uninstall_result
        exit 0
    fi    
}

function main
{
    display_license
    main_init_check
    
    # Handle SSL-only mode
    if [ "$ONLY_SSL" = "1" ]; then
        ssl_only_mode
        exit 0
    fi
    
    # Handle special actions
    action_uninstall
    if [ "$ACTION" = "PURGEALL" ] ; then
        uninstall_warn
        uninstall
        echo "Purge completed."
        exit 0
    elif [ "$ACTION" = "VERSION" ] ; then
        echo "LiteSpeed Enterprise version: $LS_VER"
        echo "Operating System: $OSNAMEVER $OSNAME $OSVER"
        echo "Architecture: $OSTYPE"
        exit 0
    fi
    
    if [ "$USER" = '' ] ; then
        if [ "$OSNAME" = "centos" ] ; then
            USER='nobody'
            GROUP='nobody'
        else
            USER='www-data'
            GROUP='www-data'
        fi
    fi
    if [ "$GROUP" = '' ] ; then
        GROUP="$USER"
    fi
    
    # Validate user exists on system and auto-fix if needed
    if ! id "$USER" >/dev/null 2>&1; then
        echo "Error: User '$USER' does not exist on this system."
        if [ "$OSNAME" = "centos" ]; then
            echo "Set user: nobody group: nobody automatically"
            USER='nobody'
            GROUP='nobody'
        else
            echo "Set user: www-data group: www-data automatically"
            USER='www-data'
            GROUP='www-data'
        fi
    fi
    
    # Also validate group exists (in case user specified custom group)
    if ! getent group "$GROUP" >/dev/null 2>&1; then
        echo "Error: Group '$GROUP' does not exist on this system."
        if [ "$OSNAME" = "centos" ]; then
            echo "Set group: nobody automatically"
            GROUP='nobody'
        else
            echo "Set group: www-data automatically"
            GROUP='www-data'
        fi
    fi    

#    # Validate parameters
#    if [ -z "$HOSTNAME" ]; then
#        echo "Error: --hostname parameter is required for SSL certificate generation."
#        echo "Usage: $0 --hostname your-domain.com --only-ssl"
#        exit 1
#    fi
    
    update_email
    main_gen_password
    
    # Check hostname availability if specified (DNS check only)
    if [ -n "$HOSTNAME" ]; then
        check_hostname_availability
    fi
    
    befor_install_display
    main_init_package
    install_litespeed
    main_lsws_password
    config_server
    change_owner ${SERVER_ROOT}
    restart_lsws
    
    if [ -n "$HOSTNAME" ]; then
        echo "LiteSpeed is now running, proceeding with SSL certificate generation..."
        check_hostname_http_connectivity  # Test port 80 connectivity
        if [ $? = 0 ] || [ "$FORCEYES" = "1" ]; then
            generate_letsencrypt_certificate
            if [ $? = 0 ]; then
                setup_certbot_auto_renewal
                # Final restart to ensure everything is applied
                echo "${FPACE} - Final restart to apply all SSL configurations"
                restart_lsws
                sleep 3
            else
                echo "Let's Encrypt certificate generation failed, using self-signed certificate"
                gen_selfsigned_cert
            fi
        else
            echo "Port 80 connectivity test failed, using self-signed certificate"
            gen_selfsigned_cert
        fi
    else
        echo "No hostname specified, generating self-signed certificate"
        gen_selfsigned_cert
    fi
    
    after_install_display
    main_lsws_test
}

while [ ! -z "${1}" ] ; do
    case "${1}" in
        -L | --license )  
                check_value_follow "$2" "license"
                if [ ! -z "$FOLLOWPARAM" ] ; then shift; fi
                LICENSE=$FOLLOWPARAM
                ;;
        --adminuser )  
                check_value_follow "$2" "admin username"
                if [ ! -z "$FOLLOWPARAM" ] ; then shift; fi
                ADMINUSER=$FOLLOWPARAM
                ;;
        -A | --adminpassword )  
                check_value_follow "$2" ""
                if [ ! -z "$FOLLOWPARAM" ] ; then shift; fi
                ADMINPASSWORD=$FOLLOWPARAM
                ;;
        --adminport )  
                check_value_follow "$2" "admin port"
                if [ ! -z "$FOLLOWPARAM" ] ; then shift; fi
                ADMINPORT=$FOLLOWPARAM
                ;;                
        -E | --email )          
                check_value_follow "$2" "email address"
                shift
                EMAIL=$FOLLOWPARAM
                ;;
        --lsphp )           
                check_value_follow "$2" "LSPHP version"
                shift
                cnt=${#LSPHPVERLIST[@]}
                for (( i = 0 ; i < cnt ; i++ )); do
                    if [ "$1" = "${LSPHPVERLIST[$i]}" ] ; then LSPHPVER=$1; fi
                done
                ;;
        --phpinstall )           
                check_value_follow "$2" "PHP installation type"
                shift
                if [ "$1" = "basic" ] || [ "$1" = "full" ]; then
                    PHPINSTALL=$1
                else
                    echo "Invalid PHP installation type. Use 'basic' or 'full'."
                    exit 1
                fi
                ;;
        --phppackages )           
                check_value_follow "$2" "PHP packages list"
                shift
                PHPPACKAGES="$1"
                ;;
        --user )           
                check_value_follow "$2" "username"
                shift
                USER=$FOLLOWPARAM
                # Auto-set group to www-data if user is www-data and group not specified
                if [ "$USER" = "www-data" ] && [ "$GROUP" = '' ]; then
                    GROUP='www-data'
                fi
                ;;
        --group )           
                check_value_follow "$2" "group name"
                shift
                GROUP=$FOLLOWPARAM
                ;;
        --httpport )           
                check_value_follow "$2" "HTTP port"
                shift
                HTTPPORT=$FOLLOWPARAM
                ;;
        --httpsport )           
                check_value_follow "$2" "HTTPS port"
                shift
                HTTPSPORT=$FOLLOWPARAM
                ;;
        --nowebports )           
                NOWEBPORTS=1
                ;;
        --hostname )           
                check_value_follow "$2" "hostname"
                shift
                HOSTNAME=$FOLLOWPARAM
                ;;
        --only-ssl )           
                ONLY_SSL=1
                ;;
        -U | --uninstall )       
                ACTION=UNINSTALL
                ;;
        -P | --purgeall )        
                ACTION=PURGEALL
                ;;
        -Q | --quiet )           
                FORCEYES=1
                ;;
        -V | --version )     
                ACTION=VERSION
                ;;
        -v | --verbose )             
                VERBOSE=1
                APT='apt-get'
                YUM='yum'
                ;;
        -H | --help )           
                usage
                ;;
        * )                     
                echo "Unknown option: $1"
                usage
                ;;
    esac
    shift
done

main
