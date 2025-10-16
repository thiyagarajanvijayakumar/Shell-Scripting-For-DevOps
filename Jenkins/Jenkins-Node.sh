#!/bin/bash

# === Jenkins Server Configuration ===
JENKINS_URL="http://54.91.5.243:8080"
AGENT_NAME="node1"
AGENT_SECRET="11c8347469f4a1152ddf335b16e10ab60218eda3a56008c2e0102fe835e07e85"
AGENT_WORKDIR="/home/jenkins_agent"

# === Install Dependencies ===
echo ">>> Updating system and installing Java..."
sudo apt update -y && sudo apt install -y openjdk-17-jre wget curl

# === Create Jenkins user and work directory ===
if ! id "jenkins" &>/dev/null; then
  echo ">>> Creating Jenkins user..."
  sudo useradd -m -d $AGENT_WORKDIR -s /bin/bash jenkins
  sudo passwd -l jenkins
fi

sudo mkdir -p $AGENT_WORKDIR
sudo chown -R jenkins:jenkins $AGENT_WORKDIR

# === Download Jenkins agent.jar ===
echo ">>> Downloading agent.jar from Jenkins master..."
sudo -u jenkins wget -q ${JENKINS_URL}/jnlpJars/agent.jar -O $AGENT_WORKDIR/agent.jar

# === Create systemd service ===
echo ">>> Creating Jenkins agent service..."
sudo tee /etc/systemd/system/jenkins-agent.service > /dev/null <<EOF
[Unit]
Description=Jenkins Agent
After=network.target

[Service]
User=jenkins
WorkingDirectory=${AGENT_WORKDIR}
ExecStart=/usr/bin/java -jar ${AGENT_WORKDIR}/agent.jar -url ${JENKINS_URL} -secret ${AGENT_SECRET} -name ${AGENT_NAME} -workDir ${AGENT_WORKDIR}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# === Enable and start service ===
echo ">>> Enabling and starting Jenkins agent service..."
sudo systemctl daemon-reload
sudo systemctl enable jenkins-agent
sudo systemctl start jenkins-agent

# === Status check ===
echo "=================================================================="
echo "✅ Jenkins Agent Node setup completed!"
echo "Agent Name : ${AGENT_NAME}"
echo "Server URL : ${JENKINS_URL}"
echo "Work Dir   : ${AGENT_WORKDIR}"
echo "=================================================================="
sudo systemctl status jenkins-agent --no-pager
echo "=================================================================="
