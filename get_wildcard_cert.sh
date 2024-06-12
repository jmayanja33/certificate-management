SCRIPT_VERSION=1.0

# Functions to log results
function log() {
  if [[ "${2}" == "" ]]; then
    echo -e "${1}"
  else
    printf "  %-55s %s\n" "${1}" "${2}"
  fi
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $*"
}

function abort() {
  exit 1
}

function test_command() {
  local message="${1}"
  local return_val=${2}

  if [[ ${return_val} -ne 0 ]]; then
    if [[ "${message}" != "" ]]; then
      log "${message}" "[FAILED]"
      log "Error; Exiting with status code: 1"
      abort
      # return
    fi
  fi

  log "${message}" "[SUCCESS]"
}

# Make sure script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

# Inform what this script does. Prompt them if they want to continue
echo ""
echo "* Script Version: $SCRIPT_VERSION *"
echo ""
echo "* This script will create a wildcard certificate for a certain domain."
echo "* The script requires a valid domain name. If you do not have one, exit now and rerun this script when a "
echo "  one is secured. If they are not, Then rerun this script. "
echo ""
echo "* You will also need to create an A record and an NS record in the DNS for this hostname before running the script."
echo "  The A record should be in the form: $HOSTNAME IN A $IP_ADDRESS"
echo "  The NS record should be in the form: $HOSTNAME IN A $HOSTNAME"
echo ""

while read -erp "Continue [y/n]: " text; do
  sanitized_text="$(echo "${text}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if [[ "${sanitized_text}" != "" ]]; then
    if [ "${sanitized_text}" == "y" ]; then
      break
    fi
    if [ "${sanitized_text}" == "n" ]; then
      exit 0
    fi
  fi
  done


# Get
echo "Enter the domain to be used: "
read -r DOMAIN
echo ""

# Get the subdomain
echo "Enter the subdomain (hostname) to be used with this domain: "
read -r HOSTNAME
echo ""

# Get Private IP Address
echo "Enter the public IP address for this server: "
read -r PUBLIC_IP
echo ""

# Get Private IP Address
echo "Enter the private IP address for this server: "
read -r PRIVATE_IP
echo ""

# Get Private IP Address
echo "Enter an email address to be used as the admin email for the certificate: "
read -r ADMIN_EMAIL
EMAIL=${EMAIL//@/.}
echo ""

# Get Private IP Address
echo "Enter the port to be used for the acme-dns server (Recommended 8080): "
read -r ACME_PORT
echo ""

# Create DNS directory
mkdir /opt/acme-dns
cd !$   # Navigates to /opt/acme-dns

# Download and extract tar with acme-dns from GitHub
curl -L -o acme-dns.tar.gz \
https://github.com/joohoi/acme-dns/releases/download/v0.8/acme-dns_0.8_linux_amd64.tar.gz
test_command "Downloading acme-dns" $?

tar -zxf acme-dns.tar.gz
test_command "Extracting acme-dns" $?
rm acme-dns.tar.gz

# Create a soft link from /opt to /usr/local/bin
ln -s /opt/acme-dns/acme-dns /usr/local/bin/acme-dns
test_command "Creating a soft link for the acme-dns" $?

# Create a minimal acme-dns user
adduser \
--system \
--gecos "acme-dns Service" \
--disabled-password \
--group \
--home /var/lib/acme-dns \
acme-dns &> NULL
test_command "Creating a minimal acme-dns user" $?

# Update the default acme-dns config with the IP from the AWS console.
# This has to be the private IP, not the public one
mkdir -p /etc/acme-dns
test_command "Creating acme-dns directory in /etc" $?
mv /opt/acme-dns/config.cfg /etc/acme-dns/
test_command "Moving acme-dns config to /etc/acme-dns" $?

# Update default listen port
sed -i "s/127.0.0.1:53/$PRIVATE_IP:53/g" /etc/acme-dns/config.cfg
test_command "Updating default acme-dns listen port" $?


# Update default auth hostname
sed -i "s/auth.example.org/$DOMAIN/g" /etc/acme-dns/config.cfg
test_command "Updating default acme-dns auth hostname" $?

# Update default admin hostname
sed -i "s/admin.example.org/$ADMIN_EMAIL/g" /etc/acme-dns/config.cfg
test_command "Updating default acme-dns admin hostname" $?

# Update default public IP
sed -i "s/198.51.100.1/$PUBLIC_IP/g" /etc/acme-dns/config.cfg
test_command "Updating acme-dns admin public IP" $?

# Update API listen port
sed -i "s/ip = \"0.0.0.0\"/\"127.0.0.1\"/g" /etc/acme-dns/config.cfg
test_command "Updating default acme-dns API listen IP to localhost" $?

# Turn off API tls
sed -i "s/tls = \"letsencryptstaging\"/tls = \"none\"/g" /etc/acme-dns/config.cfg
test_command "Turning off acme-dns API TLS" $?

# Output systemmd status
echo "* Systemd Status: "
cat acme-dns.service

# Move and reload the systemd service
mv \
test_command "Moving systemd service" $?
acme-dns.service /etc/systemd/system/acme-dns.service
systemctl daemon-reload
test_command "Reloading systemd daemon" $?

# Enable and start the acme-dns server
systemctl enable acme-dns.service %> NULL
test_command "Enabling acme-dns service" $?
systemctl start acme-dns.service
test_command "Starting acme-dns service" $?

# Check acme-dns for possible errors with either of these commands
# systemctl status acme-dns.service
# journalctl --unit acme-dns --no-pager --follow


# Use this command to test the acme-dns server is running normally
#journalctl -u acme-dns --no-pager --follow

# Try to resolve the random DNS record from localhost
dig "$HOSTNAME.$DOMAIN" &> NULL
test_command "Testing resolution of: $HOSTNAME.$DOMAIN" $?

# Make acme-dns-client folder
mkdir /opt/acme-dns-client
cd !$

# Download and extract acme-dns-client
curl -L -o acme-dns-client.tar.gz \
https://github.com/acme-dns/acme-dns-client/releases/download/v0.2/acme-dns-client_0.2_linux_amd64.tar.gz
test_command "Downloading acme-dns-client" $?

tar -zxf acme-dns-client.tar.gz
test_command "Extracting acme-dns" $?
rm acme-dns-client.tar.gz

# Create a soft link from /opt to /usr/local/bin
ln -s /opt/acme-dns-client/acme-dns-client /usr/local/bin/acme-dns-client
test_command "Creating a soft link for the acme-dns-client" $?

# Install core
snap install core; snap refresh core
test_command "Installing core" $?

# Install certbot
snap install --classic certbot
test_command "Installing certbot" $?

# Create a soft link for the certbot
ln -s /snap/bin/certbot /usr/bin/certbot
test_command "Creating a soft link for certbot" $?
