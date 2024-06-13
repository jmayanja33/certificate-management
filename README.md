# Automatically Generate a Wildcard Certificate

**<u>Latest Stable Version:</u>** v1.0

The script `get-wildcard-cert.sh` generates or renews a wildcard certificate from Let's Encrypt on a Linux server, and is based off of this: https://github.com/antonputra/tutorials/tree/main/lessons/081. The script does not auto-renew the certificate by default, but this can be configured after the script has been run. Let's Encrypt certificates are only valid for 90 days, and it is recommended they are renewed every 60 days.

The latest stable version of this script can be found in the master branch, or the branch corresponding to the version listed above.

## Server Requirements

* A server running Ubuntu 20.04 or newer, with at least 1 GB of RAM, 1 CPU, 8 GB of disk, and the following ports open:
  * 80 for HTTP
  * 443 for HTTPS
  * 22 for SSH (this can be restricted to certain IP addresses for security)
  * 53 using both TCP and UDP protocols for DNS
* If using an AWS EC2 instance:
  * An elastic IP address will need to be associated with the EC2 instance. Read more on that here: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-eips.html#allocate-eip
  * The EC2 instance will need to be on the public subnet
  * For a full tutorial on how to properly configure the EC2 instance, watch this: https://youtu.be/7jEzioFsyNo?list=RDCMUCeLvlbC754U6FyFQbKc0UnQ&t=76

## DNS Requirements

* A valid domain name
* Before executing the script, the following 2 DNS records must be created:
  * A Record
    * Set the host to 'auth'
    * Set the value to the public IP address of the server
  * NS Record
    * Set the host to 'auth'
    * Set the value to your domain with 'auth' as the subdomain (ex. 'auth.yourdomain.com')
* A third CNAME record will need to be created in the DNS when the script is executed. Be prepared to create this.

## Generating a Certificate

Follow the steps below to execute the script and generate a certificate.

1.) SSH on to your server and upload the `get-wildcard-cert.sh` script on to the server. Once finished switch to a root user (command: `sudo su`)

2.) Navigate to the directory holding the script and then run the following commands to execute

```shell
cd $PATH_TO_SCRIPT_DIRECTORY$
chmod +x get-wildcard-cert.sh  # This updates the execution permissions and only needs to be run before the first time the script is executed
./get-wildcard-cert.sh
```

3.) Once executed, the script will immediately inform you of the requirements listed above. Enter `y` to continue.

4.) Next the script will ask if an existing certificate is being renewed. Enter `n`.

5.) The script will next prompt you three pieces of information:
  * First, enter your domain (ex: yourdomain.com)
  * Next, enter the public IP address of the server
  * Next, enter the private IP address of the server
  * Next, enter an email address that will be associated with the certificate
  * Finally, enter the port number that the acme-dns server will run on (8080 is recommended, but this can be any open port).

6.) The script will then execute, follow along as it downloads and configures the acme-dns server, acme-dns client, and certbot.

7.) Once these packages have been installed, an acme-dns client will be registered
  * Enter `y` when prompted for the client to monitor CNAME record changes.
  * The script will the present you with a CNAME record. Copy this CNAME record and register it in the DNS. The host of the CNAME record should be set to '_acme_challenge' and the value should be set to the value of the record presented.
  * The script will refresh every 15 seconds until it detects the new CNAME record. Once found, it will continue on.
  * The script will then prompt you to create a CAA record. Enter `n`.

8.) The script will now request a wildcard certificate from Let's Encrypt. It will prompt you for _ pieces of information:
  * Enter the same email address entered earlier. This will be used by Let's Encrypt for renewal/security notifications.
  * Enter `y` to agree to the Terms of Service (these can be read at link presented)
  * Enter `n` if you would NOT like to share your email address with the Electronic Frontier Foundation. Enter `y` otherwise.

9.) The script will then obtain the certificate.
  * The full certificate chain can be found in `/etc/letsencrypt/live/$YOUR_DOMAIN/fullchain.pem`
  * The private key can be found in and `/etc/letsencrypt/live/$YOUR_DOMAIN/fullchain.pem`
  * Both the certificate (not the full chain) and private key will be extracted into a new directory, `generated-certificates`, which lives in the same directory that the script is being run in. These files can be downloaded and used on other servers.


## Renewing A Certificate

Follow the steps below to execute the script and renew a certificate. Note that in order to be renewed, the script must be run on the server the certificate was generated on. The original certificate/key must also still be in `/etc/letsencrypt/live/$YOUR_DOMAIN/fullchain.pem` and `/etc/letsencrypt/live/$YOUR_DOMAIN/privkey.pem`.

1.) SSH on to your server and switch to a root user (command: `sudo su`). It is assumed that the `get-wildcard-cert.sh` script is already on the server.

2.) Navigate to the directory holding the script and then run the following commands to execute

```shell
cd $PATH_TO_SCRIPT_DIRECTORY$
chmod +x get-wildcard-cert.sh  # This updates the execution permissions and only needs to be run before the first time the script is executed
./get-wildcard-cert.sh
```

3.) Once executed, the script will immediately inform you of the requirements listed above. Enter `y` to continue.

4.) Next the script will ask if an existing certificate is being renewed. Enter `y`. 
  
5.) The script will next prompt you for your domain. Enter your domain to continue (ex: yourdomain.com)

6.) The script will then execute. It will check if the original certificate is eligible for renewal, and renew it if so. Once renewed: 
  * The full certificate chain can be found in `/etc/letsencrypt/live/$YOUR_DOMAIN/fullchain.pem`
  * The private key can be found in and `/etc/letsencrypt/live/$YOUR_DOMAIN/fullchain.pem`
  * Both the certificate (not the full chain) and private key will be extracted into a new directory, `generated-certificates`, which lives in the same directory that the script is being run in. These files can be downloaded and used on other servers.


## Configure Auto-Renewal

Follow the steps here to configure auto-renewal: https://youtu.be/7jEzioFsyNo?list=RDCMUCeLvlbC754U6FyFQbKc0UnQ&t=1064

