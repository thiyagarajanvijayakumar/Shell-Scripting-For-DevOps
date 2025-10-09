#!/bin/bash

# Update and upgrade packages
sudo apt update && sudo apt upgrade -y

# Install dependencies for Nagios Core
sudo apt install -y autoconf gcc libc6 make wget unzip apache2 php libapache2-mod-php libgd-dev openssl libssl-dev

# Create and navigate to working directory
cd ~ || exit
mkdir -p nagios-core && cd nagios-core

# Download and extract Nagios Core (version 4.5.7)
wget -O nagioscore.tar.gz https://github.com/NagiosEnterprises/nagioscore/archive/nagios-4.5.7.tar.gz
tar xzf nagioscore.tar.gz
cd nagioscore-nagios-4.5.7/

# Configure, build, and install Nagios
sudo ./configure --with-httpd-conf=/etc/apache2/sites-enabled
sudo make all
sudo make install-groups-users
sudo usermod -a -G nagios www-data
sudo make install
sudo make install-daemoninit
sudo make install-commandmode
sudo make install-config
sudo make install-webconf

# Enable Apache modules
sudo a2enmod rewrite cgi

# Create web admin user
sudo htpasswd -c /usr/local/nagios/etc/htpasswd.users nagiosadmin
read -p "Enter password for nagiosadmin: " -s

# Restart Apache
sudo systemctl restart apache2

# Install Nagios Plugins dependencies
sudo apt install -y autoconf gcc libc6 libmcrypt-dev make libssl-dev wget bc gawk dc build-essential snmp libnet-snmp-perl gettext

# Download, compile, and install plugins
cd ~ || exit
wget --no-check-certificate -O nagios-plugins.tar.gz https://github.com/nagios-plugins/nagios-plugins/archive/release-2.4.12.tar.gz
tar zxf nagios-plugins.tar.gz
cd nagios-plugins-release-2.4.12
sudo ./tools/setup
sudo ./configure
sudo make && sudo make install

# Install check_nrpe plugin from NRPE source
cd ~ || exit
wget -O nrpe.tar.gz https://github.com/NagiosEnterprises/nrpe/releases/download/nrpe-4.1.3/nrpe-4.1.3.tar.gz
tar xzf nrpe.tar.gz
cd nrpe-4.1.3
sudo ./configure
sudo make check_nrpe
sudo make install-plugin

# Configure commands for NRPE
sudo bash -c 'cat << EOF > /usr/local/nagios/etc/objects/commands.cfg
define command {
    command_name    check_nrpe
    command_line    /usr/local/nagios/libexec/check_nrpe -H \$HOSTADDRESS\$ -c \$ARG1\$ -a \$ARG2\$
}
EOF'

# Configure client monitoring
sudo mkdir -p /usr/local/nagios/etc/servers
sudo bash -c 'cat << EOF > /usr/local/nagios/etc/servers/client.cfg
define host {
    use                 linux-server
    host_name           ubuntu-client
    alias               Ubuntu Client Server
    address             3.91.52.2
    max_check_attempts  5
    check_period        24x7
    notification_interval 30
    notification_period 24x7
}

define service {
    use                 generic-service
    host_name           ubuntu-client
    service_description Check Disk
    check_command       check_nrpe!check_disk
}

define service {
    use                 generic-service
    host_name           ubuntu-client
    service_description Check Load
    check_command       check_nrpe!check_load
}

define service {
    use                 generic-service
    host_name           ubuntu-client
    service_description Check Memory
    check_command       check_nrpe!check_mem
}
EOF'

# Update nagios.cfg to include client config
echo "cfg_dir=/usr/local/nagios/etc/servers" | sudo tee -a /usr/local/nagios/etc/nagios.cfg

# Verify configuration and start Nagios
sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg
sudo systemctl enable nagios
sudo systemctl start nagios

# Configure firewall
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw enable
sudo ufw reload

echo "Nagios installation and configuration completed on main server (54.167.86.47)."