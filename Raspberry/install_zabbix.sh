#!/bin/bash

# Exit on any error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check if running as non-root with sudo
if [ "$(id -u)" -eq 0 ]; then
    echo -e "${RED}This script must be run as a non-root user with sudo privileges.${NC}"
    exit 1
fi

# Prompt for Zabbix database password
echo -e "${GREEN}Enter a strong password for the Zabbix database:${NC}"
read -s DB_PASSWORD
if [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}Password cannot be empty!${NC}"
    exit 1
fi
echo

# Update system
echo -e "${GREEN}Updating system...${NC}"
sudo apt update && sudo apt upgrade -y

# Install dependencies
echo -e "${GREEN}Installing Apache, MariaDB, PHP, and dependencies...${NC}"
sudo apt install -y apache2 mariadb-server php php-mysql php-gd php-xml php-bcmath php-mbstring php-ldap php-json

# Secure MariaDB (non-interactive)
echo -e "${GREEN}Securing MariaDB...${NC}"
sudo mysql -e "UPDATE mysql.user SET Password=PASSWORD('$DB_PASSWORD') WHERE User='root';"
sudo mysql -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -e "DROP DATABASE IF EXISTS test;"
sudo mysql -e "FLUSH PRIVILEGES;"

# Add Zabbix repository
echo -e "${GREEN}Adding Zabbix 7.0 repository...${NC}"
wget https://repo.zabbix.com/zabbix/7.0/raspbian/pool/main/z/zabbix-release/zabbix-release_7.0-5+debian12_all.deb
sudo dpkg -i zabbix-release_7.0-5+debian12_all.deb
sudo apt update

# Install Zabbix components
echo -e "${GREEN}Installing Zabbix server, frontend, and agent...${NC}"
sudo apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent

# Configure database
echo -e "${GREEN}Creating Zabbix database and user...${NC}"
sudo mysql -u root -p"$DB_PASSWORD" -e "CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
sudo mysql -u root -p"$DB_PASSWORD" -e "CREATE USER 'zabbix'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
sudo mysql -u root -p"$DB_PASSWORD" -e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';"
sudo mysql -u root -p"$DB_PASSWORD" -e "FLUSH PRIVILEGES;"

# Import database schema
echo -e "${GREEN}Importing Zabbix database schema...${NC}"
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p"$DB_PASSWORD" zabbix

# Configure Zabbix server
echo -e "${GREEN}Configuring Zabbix server...${NC}"
sudo sed -i "s/# DBPassword=/DBPassword=$DB_PASSWORD/" /etc/zabbix/zabbix_server.conf

# Configure PHP settings
echo -e "${GREEN}Configuring PHP settings...${NC}"
PHP_INI="/etc/php/8.2/apache2/php.ini"
sudo sed -i 's/post_max_size = .*/post_max_size = 16M/' "$PHP_INI"
sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
sudo sed -i 's/max_input_time = .*/max_input_time = 300/' "$PHP_INI"
sudo sed -i 's/#date.timezone =/date.timezone = America\/New_York/' "$PHP_INI" # Adjust timezone as needed
sudo sed -i 's/memory_limit = .*/memory_limit = 128M/' "$PHP_INI"
sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 2M/' "$PHP_INI"

# Restart Apache
echo -e "${GREEN}Restarting Apache...${NC}"
sudo systemctl restart apache2

# Start and enable Zabbix services
echo -e "${GREEN}Starting and enabling Zabbix services...${NC}"
sudo systemctl start zabbix-server zabbix-agent apache2
sudo systemctl enable zabbix-server zabbix-agent apache2

# Output final instructions
PI_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}Zabbix installation complete!${NC}"
echo -e "Access the web interface at: ${GREEN}http://$PI_IP/zabbix${NC}"
echo -e "Default login: Username = ${GREEN}Admin${NC}, Password = ${GREEN}zabbix${NC} (change immediately)"
echo -e "To monitor this Pi, go to Configuration > Hosts > Create host, use IP $PI_IP, port 10050, and link the 'Raspbian by Zabbix agent' template."
echo -e "Check logs if issues arise: ${GREEN}/var/log/zabbix/zabbix_server.log${NC}"
