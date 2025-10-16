#!/bin/bash

# Update system
sudo apt update -y && sudo apt upgrade -y

# Install dependencies
sudo apt install -y fontconfig openjdk-17-jre wget gnupg2

# Add Jenkins repo key and source list
wget -q -O - https://pkg.jenkins.io/debian/jenkins.io-2023.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

# Update and install Jenkins
sudo apt update -y
sudo apt install -y jenkins

# Enable and start Jenkins service
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Display status
sudo systemctl status jenkins --no-pager

# Print initial admin password
echo "=================================================================="
echo "Jenkins Installation Completed!"
echo "Access Jenkins: http://<your-server-ip>:8080"
echo "Initial Admin Password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
echo "=================================================================="
