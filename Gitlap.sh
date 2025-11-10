#!/bin/bash
# GitLab CE installation script for Ubuntu 22.04 EC2 instance

set -e

echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y

echo "Installing dependencies..."
apt-get install -y curl openssh-server ca-certificates tzdata perl

echo "Installing Postfix for email notifications..."
DEBIAN_FRONTEND=noninteractive apt-get install -y postfix

echo "Adding GitLab CE repository..."
curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash

echo "Installing GitLab CE..."
EXTERNAL_URL="http://34.229.61.75" apt-get install -y gitlab-ce

echo "Reconfiguring GitLab..."
gitlab-ctl reconfigure

echo "GitLab installation completed."
echo "Access URL: http://34.229.61.75"
echo "Root password stored at: /etc/gitlab/initial_root_password"
