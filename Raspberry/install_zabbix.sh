#!/bin/bash

# Consolidated Zabbix Installation and Mattermost Alerts Configuration Script for Raspberry Pi (Debian 12/Bookworm)

# Exit on error
set -e

# Function to check if command executed successfully
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error: $1"
        exit 1
    fi
}

# Prompt for database password
read -sp "Enter a strong password for the Zabbix database user: " DB_PASSWORD
echo
if [ -z "$DB_PASSWORD" ]; then
    echo "Error: Password cannot be empty."
    exit 1
fi

# Prompt for timezone
read -p "Enter your timezone (e.g., Europe/London): " TIMEZONE
if [ -z "$TIMEZONE" ]; then
    TIMEZONE="UTC"
    echo "No timezone provided, defaulting to UTC."
fi

# Prompt for Mattermost details
read -p "Enter your Mattermost URL (e.g., https://your-mattermost.com): " MATTERMOST_URL
if [ -z "$MATTERMOST_URL" ]; then
    echo "Error: Mattermost URL cannot be empty."
    exit 1
fi

read -sp "Enter your Mattermost Bot Access Token: " BOT_TOKEN
echo
if [ -z "$BOT_TOKEN" ]; then
    echo "Error: Bot token cannot be empty."
    exit 1
fi

read -p "Enter Mattermost team and channel (e.g., general/#alerts or channel ID): " SEND_TO
if [ -z "$SEND_TO" ]; then
    echo "Error: Team/channel cannot be empty."
    exit 1
fi

echo "Starting Zabbix installation and Mattermost configuration..."

# Step 1: Update system
echo "Updating system packages..."
sudo apt update
check_status "Failed to update package lists."
sudo apt full-upgrade -y
check_status "Failed to upgrade packages."

# Install jq for JSON parsing (needed for Mattermost API calls)
echo "Installing jq..."
sudo apt install jq -y
check_status "Failed to install jq."

# Step 2: Install MariaDB
echo "Installing MariaDB..."
sudo apt install mariadb-server mariadb-client -y
check_status "Failed to install MariaDB."

# Secure MariaDB installation
echo "Securing MariaDB installation..."
sudo mysql_secure_installation <<EOF

y
$DB_PASSWORD
$DB_PASSWORD
y
y
y
y
EOF
check_status "Failed to secure MariaDB."

# Create Zabbix database and user
echo "Creating Zabbix database and user..."
sudo mysql -u root -p"$DB_PASSWORD" -e "
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;"
check_status "Failed to create Zabbix database or user."

# Step 3: Install NGINX and PHP
echo "Installing NGINX and PHP..."
sudo apt install nginx php php-mysql php-gd php-xml php-bcmath php-mbstring php-ldap php-json php-curl php-apcu php-dom -y
check_status "Failed to install NGINX and PHP."

# Configure PHP
PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
PHP_INI="/etc/php/$PHP_VERSION/fpm/php.ini"
echo "Configuring PHP in $PHP_INI..."
sudo sed -i "s/memory_limit = .*/memory_limit = 128M/" $PHP_INI
sudo sed -i "s/post_max_size = .*/post_max_size = 16M/" $PHP_INI
sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 2M/" $PHP_INI
sudo sed -i "s/max_execution_time = .*/max_execution_time = 300/" $PHP_INI
sudo sed -i "s/max_input_time = .*/max_input_time = 300/" $PHP_INI
sudo sed -i "s|;date.timezone =.*|date.timezone = $TIMEZONE|" $PHP_INI
check_status "Failed to configure PHP."

# Restart NGINX and PHP-FPM
echo "Restarting NGINX and PHP-FPM..."
sudo systemctl restart nginx php${PHP_VERSION}-fpm
check_status "Failed to restart NGINX or PHP-FPM."

# Step 4: Install Zabbix
echo "Adding Zabbix repository..."
wget https://repo.zabbix.com/zabbix/7.0/raspbian/pool/main/z/zabbix-release/zabbix-release_7.0-1+debian12_all.deb
check_status "Failed to download Zabbix repository package."
sudo dpkg -i zabbix-release_7.0-1+debian12_all.deb
check_status "Failed to install Zabbix repository package."
sudo apt update
check_status "Failed to update package lists after adding Zabbix repository."

echo "Installing Zabbix packages..."
sudo apt install zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent -y
check_status "Failed to install Zabbix packages."

# Import Zabbix database schema
echo "Importing Zabbix database schema..."
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p"$DB_PASSWORD" zabbix
check_status "Failed to import Zabbix database schema."

# Configure Zabbix server
echo "Configuring Zabbix server..."
sudo sed -i "s/# DBPassword=/DBPassword=$DB_PASSWORD/" /etc/zabbix/zabbix_server.conf
check_status "Failed to configure Zabbix server."

# Configure NGINX for Zabbix
echo "Configuring NGINX for Zabbix..."
sudo sed -i 's/# listen 80;/listen 80;/' /etc/zabbix/nginx.conf
sudo sed -i 's/# server_name _;/server_name _;/' /etc/zabbix/nginx.conf
check_status "Failed to configure NGINX for Zabbix."

# Ensure Zabbix NGINX config is included
if ! grep -q "include /etc/zabbix/nginx.conf" /etc/nginx/nginx.conf; then
    sudo sed -i '/http {/a \    include /etc/zabbix/nginx.conf;' /etc/nginx/nginx.conf
    check_status "Failed to add Zabbix NGINX config to nginx.conf."
fi

# Restart and enable services
echo "Restarting and enabling services..."
sudo systemctl restart zabbix-server zabbix-agent nginx php${PHP_VERSION}-fpm
check_status "Failed to restart services."
sudo systemctl enable zabbix-server zabbix-agent nginx php${PHP_VERSION}-fpm
check_status "Failed to enable services."

# Step 5: Configure Mattermost Alerts
echo "Configuring Zabbix for Mattermost alerts..."

# Download Mattermost media type YAML
echo "Downloading Mattermost media type YAML..."
wget https://git.zabbix.com/projects/ZBX/repos/zabbix/raw/templates/media/mattermost/media_mattermost.yaml -O /tmp/media_mattermost.yaml
check_status "Failed to download Mattermost media type YAML."

# Import Mattermost media type
echo "Importing Mattermost media type..."
zabbix_api_import() {
    # Log in to Zabbix API (default Admin credentials; assumes password changed manually)
    AUTH_TOKEN=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "user.login",
        "params": {
            "username": "Admin",
            "password": "zabbix"
        },
        "id": 1
    }' http://127.0.0.1/zabbix/api_jsonrpc.php | jq -r '.result')

    if [ -z "$AUTH_TOKEN" ]; then
        echo "Error: Failed to authenticate with Zabbix API."
        exit 1
    }

    # Import YAML
    curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "configuration.import",
        "params": {
            "format": "yaml",
            "rules": {
                "media_types": {
                    "createMissing": true,
                    "updateExisting": true
                }
            },
            "source": "'"$(cat /tmp/media_mattermost.yaml | sed 's/"/\\"/g')"'"
        },
        "auth": "'"$AUTH_TOKEN"'",
        "id": 2
    }' http://127.0.0.1/zabbix/api_jsonrpc.php
}
zabbix_api_import
check_status "Failed to import Mattermost media type."

# Configure Mattermost media type
echo "Configuring Mattermost media type..."
zabbix_api_configure_media() {
    AUTH_TOKEN=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "user.login",
        "params": {
            "username": "Admin",
            "password": "zabbix"
        },
        "id": 1
    }' http://127.0.0.1/zabbix/api_jsonrpc.php | jq -r '.result')

    MEDIA_TYPE_ID=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "mediatype.get",
        "params": {
            "filter": {"name": "Mattermost"}
        },
        "auth": "'"$AUTH_TOKEN"'",
        "id": 3
    }' http://127.0.0.1/zabbix/api_jsonrpc.php | jq -r '.result[0].mediatypeid')

    curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "mediatype.update",
        "params": {
            "mediatypeid": "'"$MEDIA_TYPE_ID"'",
            "parameters": [
                {"name": "bot_token", "value": "'"$BOT_TOKEN"'"},
                {"name": "mattermost_url", "value": "'"$MATTERMOST_URL"'"}
            ]
        },
        "auth": "'"$AUTH_TOKEN"'",
        "id": 4
    }' http://127.0.0.1/zabbix/api_jsonrpc.php
}
zabbix_api_configure_media
check_status "Failed to configure Mattermost media type."

# Add Mattermost media to Admin user
echo "Adding Mattermost media to Admin user..."
zabbix_api_add_user_media() {
    AUTH_TOKEN=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "user.login",
        "params": {
            "username": "Admin",
            "password": "zabbix"
        },
        "id": 1
    }' http://127.0.0.1/zabbix/api_jsonrpc.php | jq -r '.result')

    USER_ID=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "user.get",
        "params": {
            "filter": {"username": "Admin"}
        },
        "auth": "'"$AUTH_TOKEN"'",
        "id": 5
    }' http://127.0.0.1/zabbix/api_jsonrpc.php | jq -r '.result[0].userid')

    MEDIA_TYPE_ID=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "mediatype.get",
        "params": {
            "filter": {"name": "Mattermost"}
        },
        "auth": "'"$AUTH_TOKEN"'",
        "id": 6
    }' http://127.0.0.1/zabbix/api_jsonrpc.php | jq -r '.result[0].mediatypeid')

    curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "user.updatemedia",
        "params": {
            "users": [{"userid": "'"$USER_ID"'"}],
            "medias": [{
                "mediatypeid": "'"$MEDIA_TYPE_ID"'",
                "sendto": "'"$SEND_TO"'",
                "active": 0,
                "severity": 63,
                "period": "1-7,00:00-24:00"
            }]
        },
        "auth": "'"$AUTH_TOKEN"'",
        "id": 7
    }' http://127.0.0.1/zabbix/api_jsonrpc.php
}
zabbix_api_add_user_media
check_status "Failed to add Mattermost media to Admin user."

# Create Mattermost alert action
echo "Creating Mattermost alert action..."
zabbix_api_create_action() {
    AUTH_TOKEN=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "user.login",
        "params": {
            "username": "Admin",
            "password": "zabbix"
        },
        "id": 1
    }' http://127.0.0.1/zabbix/api_jsonrpc.php | jq -r '.result')

    curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "action.create",
        "params": {
            "name": "Mattermost Alerts",
            "eventsource": 0,
            "status": 0,
            "esc_period": "1h",
            "filter": {
                "evaltype": 0,
                "conditions": [
                    {
                        "conditiontype": 3,
                        "operator": 2,
                        "value": "4"
                    }
                ]
            },
            "operations": [
                {
                    "operationtype": 0,
                    "opmessage": {
                        "default_msg": 1,
                        "mediatypeid": "'"$MEDIA_TYPE_ID"'"
                    },
                    "opmessage_usr": [{"userid": "'"$USER_ID"'"}]
                }
            ]
        },
        "auth": "'"$AUTH_TOKEN"'",
        "id": 8
    }' http://127.0.0.1/zabbix/api_jsonrpc.php
}
zabbix_api_create_action
check_status "Failed to create Mattermost alert action."

echo "Zabbix installation and Mattermost alerts configuration completed successfully!"
echo "Please complete the following manual steps after reboot:"

# Instructions for manual steps
cat << EOF
Manual Steps to Complete Zabbix Setup:
1. Complete Zabbix Web Setup:
   - Access http://<your-pi-ip>/zabbix (find IP with 'hostname -I').
   - Follow the wizard:
     - Welcome: Next.
     - Prerequisites: Ensure all OK, Next.
     - Database: Name 'zabbix', User 'zabbix', Password '$DB_PASSWORD', Next.
     - Server details: Default, Next.
     - GUI settings: Set timezone to '$TIMEZONE', Next.
     - Summary: Next.
     - Finish.
   - Log in with Username: Admin, Password: zabbix.
   - Change Admin password under Administration > Users > Admin.

2. Set Up Mattermost Bot:
   - In Mattermost: Main Menu > Integrations > Bot Accounts > Add Bot Account.
   - Name: ZabbixBot, enable post:all and post:channels.
   - Copy Access Token (already provided to script: $BOT_TOKEN).
   - Invite bot to team/channel: $SEND_TO.

3. Add Host for Raspberry Pi:
   - Go to Data collection > Hosts > Create host.
   - Host name: RaspberryPi.
   - Groups: Add to Linux servers.
   - Interfaces: Add Agent, IP 127.0.0.1, Port 10050.
   - Templates: Link Template OS Linux by Zabbix agent.
   - Update.

4. Create Custom Triggers:
   - Go to Data collection > Hosts > RaspberryPi > Triggers > Create trigger.
   - No Data (60s):
     - Name: No Data Alert
     - Expression: {RaspberryPi:agent.ping.nodata(60s)}=1
     - Severity: High
   - Low Disk (<5GB free on /):
     - Name: Low Disk Space
     - Expression: {RaspberryPi:vfs.fs.size[/,free].last()}<5G
     - Severity: High
   - High RAM (>75%):
     - Name: High RAM Usage
     - Expression: {RaspberryPi:vm.memory.size[used].avg(5m)}/{RaspberryPi:vm.memory.size[total].last()}*100>75
     - Severity: High
   - Update each.

5. Create Graphs:
   - Go to Data collection > Hosts > RaspberryPi > Graphs > Create graph.
   - CPU Utilization (5m):
     - Add item: system.cpu.util[,user].avg(5m)
   - Memory Total/Free:
     - Add items: vm.memory.size[total], vm.memory.size[free]
   - Repeat for other metrics as needed.

6. Test Alerts:
   - Stress the Pi: 'stress --cpu 4 --timeout 60' or stop agent: 'sudo systemctl stop zabbix-agent'.
   - Check Monitoring > Problems and Mattermost channel ($SEND_TO) for alerts.
   - Restart agent if stopped: 'sudo systemctl start zabbix-agent'.

Note: If you changed the Admin password, update it in the Zabbix API calls within this script for future runs.
The system will now reboot to apply changes.
EOF

# Reboot system
echo "Rebooting system..."
sudo reboot
