#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero

# Step 1: Switch to root 
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo -i"
  exit 1
fi

echo "Starting WHM/cPanel installation..."

# Step 2: Update and upgrade system
apt update && apt upgrade -y

# Step 3: Set hostname
read -p "Enter your desired hostname (e.g., whm.example.com): " HOSTNAME
hostnamectl set-hostname "$HOSTNAME"

# Step 4: Add IP and hostname to /etc/hosts
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)
echo "$PUBLIC_IP $HOSTNAME" >> /etc/hosts

# Step 5: Install dependencies
apt install perl curl -y

# Step 6: Disable AppArmor
systemctl stop apparmor || true
systemctl disable apparmor || true

# Step 7: Download and install WHM/cPanel
cd /home
curl -o latest -L https://securedownloads.cpanel.net/latest
sh latest

