SCRIPT_VERSION=1.0
CWD=$(pwd)

# Functions to log results
function log() {
  if [[ "${2}" == "" ]]; then
    echo -e "${1}"
  else
    printf "  %-55s %s\n" "${1}" "${2}"
  fi
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
      return
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
echo "* This script will create or renew a wildcard certificate for a certain domain."
echo "* The script requires a valid domain name. If you do not have one, exit now and rerun this script when "
echo "  one is secured. Then rerun this script. "
echo ""
echo "* You will also need to create an A record and an NS record in the DNS for this hostname before running the script."
echo "  The A record should be in the form: \$DOMAIN IN A \$IP_ADDRESS"
echo "  The NS record should be in the form: \$DOMAIN IN NS \$HOSTNAME"
echo ""
echo "* When the certificate is being generated, you will need to add a CNAME record to the DNS that is provided. Please"
echo "  be prepared to do this."
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


echo ""
echo "Is this a certificate renewal?"
echo""
while read -erp "Renewal [y/n]: " text; do
  sanitized_text="$(echo "${text}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if [[ "${sanitized_text}" != "" ]]; then
    if [ "${sanitized_text}" == "y" ]; then

      # Get the domain
      echo ""
      echo "Enter the domain to be used (ex: example.com): "
      read -r DOMAIN
      echo ""

      # Renew certificate
      certbot renew --manual --preferred-challenges dns --manual-auth-hook 'acme-dns-client'
      test_command "Renewing Certificate" $?

      # Check for existing certificate
      if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        echo ""
        log "Finding Certificate" "[SUCCESS]"
      else
        echo ""
        log "Finding Certificate" "[FAILED]"
        log "Error; Unable to find the certificate. Make sure the certificate was generated on this server."
        exit 1
      fi

      # Set certificate export variables
      CERT_FILENAME=${DOMAIN//./-}
      CERT_DIR="$CWD/generated-certificates/$CERT_FILENAME"

      # Create certificate directory
      if [ -d "$CWD/generated-certificates" ]; then
        :
      else
        mkdir "$CWD/generated-certificates"
      fi
      # Create domain directory in certificate folder
      if [ -d "$CWD/generated-certificates/$CERT_FILENAME" ]; then
        :
      else
        mkdir "$CWD/generated-certificates/$CERT_FILENAME"
      fi

      # Extract certificate and RSA/EC private key
      openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -out "$CERT_DIR/$CERT_FILENAME-wildcard-certificate.pem" -nokeys
      test_command "Saving certificate to ${CWD}/${CERT_FILENAME}-wildcard-certificate.pem" $?

      # openssl rsa -in "/etc/letsencrypt/live/$DOMAIN/privkey.pem" -out "$CERT_DIR/$CERT_FILENAME-rsa-private-key.pem"
      # test_command "Saving RSA private key to ${CWD}/${CERT_FILENAME}-rsa-private-key.pem" $?

      openssl ec -in "/etc/letsencrypt/live/$DOMAIN/privkey.pem" -out "$CERT_DIR/$CERT_FILENAME-ec-private-key.pem"
      test_command "Saving EC private key to ${CWD}/${CERT_FILENAME}-ec-private-key.pem" $?

      echo ""
      log "Script completed with exit code 0"
      exit 0
    fi
    if [ "${sanitized_text}" == "n" ]; then
      break
    fi
  fi
  done


# Get the domain
echo ""
echo "Enter the domain to be used (ex: example.com): "
read -r DOMAIN
echo ""

# Get Public IP Address
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
ADMIN_EMAIL=${ADMIN_EMAIL//@/.}
echo ""

# Get Private IP Address
echo "Enter the port to be used for the acme-dns server: "
read -r ACME_PORT
echo ""

# Create acme-dns directory
if [ -d /opt/acme-dns ]; then
  :
else
  mkdir /opt/acme-dns
fi
# shellcheck disable=SC2164
cd /opt/acme-dns

# Download and extract tar with acme-dns from GitHub
curl -L -o acme-dns.tar.gz \
https://github.com/joohoi/acme-dns/releases/download/v0.8/acme-dns_0.8_linux_amd64.tar.gz
test_command "Downloading acme-dns" $?

tar -zxf acme-dns.tar.gz
test_command "Extracting acme-dns" $?
rm acme-dns.tar.gz

# Create a soft link from /opt to /usr/local/bin
if [ -f /usr/local/bin/acme-dns ]; then
  log "Creating a soft link for the acme-dns" "[EXISTS]"
else
  ln -s /opt/acme-dns/acme-dns /usr/local/bin/acme-dns
  test_command "Creating a soft link for the acme-dns" $?
fi

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
mv /opt/acme-dns/config.cfg /etc/acme-dns
test_command "Moving acme-dns config to /etc/acme-dns" $?

# Update default listen port
sed -i "s/127.0.0.1:53/${PRIVATE_IP}:53/g" /etc/acme-dns/config.cfg
test_command "Updating default acme-dns listen port" $?

# Update default auth hostname
sed -i "s/auth.example.org/auth.${DOMAIN}/g" /etc/acme-dns/config.cfg
test_command "Updating default acme-dns auth hostname" $?

# Update default admin hostname
sed -i "s/admin.example.org/${ADMIN_EMAIL}/g" /etc/acme-dns/config.cfg
test_command "Updating default acme-dns admin hostname" $?

# Update default public IP
sed -i "s/198.51.100.1/${PUBLIC_IP}/g" /etc/acme-dns/config.cfg
test_command "Updating acme-dns admin public IP" $?

# Update API listen IP
sed -i "s/ip = \"0.0.0.0\"/ip = \"127.0.0.1\"/g" /etc/acme-dns/config.cfg
test_command "Updating default acme-dns API listen IP to localhost" $?

# Update API listen port
sed -i "s/port = \"443\"/port = \"${ACME_PORT}\"/g" /etc/acme-dns/config.cfg
test_command "Updating default acme-dns API listen port to ${ACME_PORT}" $?

# Turn off API tls
sed -i "s/tls = \"letsencryptstaging\"/tls = \"none\"/g" /etc/acme-dns/config.cfg
test_command "Turning off acme-dns API TLS" $?

# Output acme-dns.service status
echo ""
echo "----- ACME-DNS.SERVICE STATUS ----- "
cat acme-dns.service
echo "----------- END STATUS -----------"
echo ""

# Move and reload the systemd service
mv acme-dns.service /etc/systemd/system/acme-dns.service
test_command "Moving acme-dns.service to /etc/systemd" $?
systemctl daemon-reload
test_command "Reloading systemd daemon" $?

# Enable and start the acme-dns server
# Check the status of the acme-dns service
if systemctl is-active --quiet acme-dns; then
    systemctl restart acme-dns
    test_command "Starting acme-dns service" $?
else
    systemctl enable acme-dns.service &> NULL
    test_command "Enabling acme-dns service" $?
    systemctl start acme-dns.service &> NULL
    test_command "Starting acme-dns service" $?
fi

# Check acme-dns for possible errors with either of these commands
# systemctl status acme-dns.service
# journalctl --unit acme-dns --no-pager --follow


# Use this command to test the acme-dns server is running normally
#journalctl -u acme-dns --no-pager --follow

# Try to resolve the random DNS record from localhost
#TEST_URL=${DOMAIN//*/}
# log "Testing resolution of ${TEST_URL}:"
#dig "${TEST_URL}"

# Make acme-dns-client folder
if [ -d /opt/acme-dns-client ]; then
  :
else
  mkdir /opt/acme-dns-client
fi
# shellcheck disable=SC2164
cd /opt/acme-dns-client

# Download and extract acme-dns-client
curl -L -o acme-dns-client.tar.gz \
https://github.com/acme-dns/acme-dns-client/releases/download/v0.2/acme-dns-client_0.2_linux_amd64.tar.gz
test_command "Downloading acme-dns-client" $?

tar -zxf acme-dns-client.tar.gz
test_command "Extracting acme-dns" $?
rm acme-dns-client.tar.gz

# Create a soft link from /opt to /usr/local/bin
if [ -f /usr/local/bin/acme-dns-client ]; then
  log "Creating a soft link for the acme-dns-client" "[EXISTS]"
else
  ln -s /opt/acme-dns-client/acme-dns-client /usr/local/bin/acme-dns-client
  test_command "Creating a soft link for the acme-dns-client" $?
fi

# Install core
snap install core &> NULL
test_command "Installing core" $?
snap refresh core &> NULL
test_command "Updating core" $?

# Install certbot
snap install --classic certbot &> NULL
test_command "Installing certbot" $?

# Create a soft link for the certbot
if [ -f /usr/bin/certbot ]; then
  log "Creating a soft link for the acme-dns-client" "[EXISTS]"
else
  ln -s /snap/bin/certbot /usr/bin/certbot
  test_command "Creating a soft link for the certbot" $?
fi

# Create a new acme-dns account for the domain
echo ""
echo "Creating DNS account for ${DOMAIN}:"
echo ""

acme-dns-client register -d "$DOMAIN" -s "http://127.0.0.1:$ACME_PORT"
test_command "Creating DNS account for ${DOMAIN}" $?

# Check acme dns record
echo ""
echo "----- CHECKING DNS RECORD: -----"
dig "_acme-challenge.$DOMAIN"
echo "---------- END CHECK -----------"
echo ""

# Get wildcard certificate
echo ""
echo "Generating wildcard certificate for *.${DOMAIN}"
echo ""

certbot certonly \
  --manual \
  --preferred-challenges dns \
  --manual-auth-hook 'acme-dns-client' \
  -d "*.$DOMAIN"
test_command "Generating wildcard certificate for *.${DOMAIN}" $?

# Set certificate export variables
CERT_FILENAME=${DOMAIN//./-}
CERT_DIR="$CWD/generated-certificates/$CERT_FILENAME"

# Create certificate directory
if [ -d "$CWD/generated-certificates" ]; then
  :
else
  mkdir "$CWD/generated-certificates"
fi

# Create domain directory in certificate folder
if [ -d "$CWD/generated-certificates/$CERT_FILENAME" ]; then
  :
else
  mkdir "$CWD/generated-certificates/$CERT_FILENAME"
fi

# Extract certificate and RSA/EC private key
openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -out "$CERT_DIR/$CERT_FILENAME-wildcard-certificate.pem" -nokeys
test_command "Saving certificate to ${CWD}/${CERT_FILENAME}-wildcard-certificate.pem" $?

# openssl rsa -in "/etc/letsencrypt/live/$DOMAIN/privkey.pem" -out "$CERT_DIR/$CERT_FILENAME-rsa-private-key.pem"
# test_command "Saving RSA private key to ${CWD}/${CERT_FILENAME}-rsa-private-key.pem" $?

openssl ec -in "/etc/letsencrypt/live/$DOMAIN/privkey.pem" -out "$CERT_DIR/$CERT_FILENAME-ec-private-key.pem"
test_command "Saving EC private key to ${CWD}/${CERT_FILENAME}-ec-private-key.pem" $?

## Test automatic renewal
#echo ""
#echo "----- TESTING AUTO-RENEWAL: -----"
#certbot renew \
#  --manual \
#  --test-cert \
#  --dry-run \
#  --preferred-challenges dns \
#  --manual-auth-hook 'acme-dns-client'
#echo "---------- END TEST --------------"
#echo ""
#test_command "Testing automatic certificate renewal" $?

echo ""

log "Script completed with exit code 0"
