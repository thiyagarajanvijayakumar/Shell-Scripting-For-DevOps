#!/bin/bash

# Update and upgrade packages
sudo apt update && sudo apt upgrade -y

# Install NRPE and Nagios plugins
sudo apt install -y nagios-nrpe-server nagios-plugins

# Enable and start NRPE service
sudo systemctl enable --now nagios-nrpe-server

# Configure NRPE to allow main server (54.167.86.47)
sudo sed -i "s/^allowed_hosts=.*/allowed_hosts=127.0.0.1,::1,54.167.86.47/" /etc/nagios/nrpe.cfg

# Add custom commands for monitoring
echo "command[check_disk]=/usr/lib/nagios/plugins/check_disk -w 20% -c 10% -p /" | sudo tee -a /etc/nagios/nrpe.cfg
echo "command[check_load]=/usr/lib/nagios/plugins/check_load -w 5.0,4.0,3.0 -c 10.0,8.0,6.0" | sudo tee -a /etc/nagios/nrpe.cfg
echo "command[check_mem]=/usr/lib/nagios/plugins/check_mem -w 80 -c 90" | sudo tee -a /etc/nagios/nrpe.cfg

# Restart NRPE service
sudo systemctl restart nagios-nrpe-server

# Configure firewall to allow main server
sudo ufw allow from 54.167.86.47 to any port 5666 proto tcp
sudo ufw reload

echo "NRPE installation and configuration completed on client server (3.91.52.2)."