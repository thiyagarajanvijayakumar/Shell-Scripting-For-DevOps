#!/bin/bash
set -e

# Jenkins Master Details
JENKINS_URL="http://54.211.39.23:8080"
AGENT_NAME="node1"
AGENT_SECRET="6befbb0a2ce5666ea708dcfb376079d42ae12e7b06f84e958e9b25c9830369ae"
AGENT_WORKDIR="/home/jenkins"
AGENT_JAR="${AGENT_WORKDIR}/agent.jar"

# Install Dependencies
sudo apt update -y
sudo apt install -y openjdk-17-jre curl

# Create Jenkins user and directory
sudo useradd -m -d ${AGENT_WORKDIR} -s /bin/bash jenkins
sudo mkdir -p ${AGENT_WORKDIR}
sudo chown -R jenkins:jenkins ${AGENT_WORKDIR}

# Download Jenkins agent JAR
sudo -u jenkins curl -sLo ${AGENT_JAR} ${JENKINS_URL}/jnlpJars/agent.jar

# Create systemd service
cat <<EOF | sudo tee /etc/systemd/system/jenkins-agent.service
[Unit]
Description=Jenkins Agent Service
After=network.target

[Service]
User=jenkins
WorkingDirectory=${AGENT_WORKDIR}
ExecStart=/usr/bin/java -jar ${AGENT_JAR} -url ${JENKINS_URL} -secret ${AGENT_SECRET} -name ${AGENT_NAME} -webSocket -workDir "${AGENT_WORKDIR}"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start agent
sudo systemctl daemon-reload
sudo systemctl enable jenkins-agent
sudo systemctl start jenkins-agent

echo "==============================================================="
echo "✅ Fresh Jenkins Agent Installed Successfully!"
echo "Agent Name : ${AGENT_NAME}"
echo "Server URL : ${JENKINS_URL}"
echo "Work Dir   : ${AGENT_WORKDIR}"
echo "==============================================================="
