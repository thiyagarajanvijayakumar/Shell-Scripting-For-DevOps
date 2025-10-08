#!/bin/bash
set -e  

<< task
Deploy a Dockerfile and host a webserver automatically
task

code_clone() {
    echo "Cloning the docker repo..."
    if [ -d "Cron-Job-Docker" ]; then
        echo "Repository already exists — removing old copy..."
        rm -rf Cron-Job-Docker
    fi
    git clone https://github.com/thiyagarajanvijayakumar/Cron-Job-Docker.git
}

install_requirements() {
    echo "Installing dependencies..."
    sudo apt-get update -y
    sudo apt-get install docker.io -y
    sudo systemctl start docker
    sudo systemctl enable docker
}

required_restarts() {
    echo "Restarting Docker service..."
    sudo systemctl restart docker
}

deploy() {
    echo "Building and running Docker container..."
    cd Cron-Job-Docker || { echo "Repo not found!"; exit 1; }

    # Make sure Dockerfile exists
    if [ ! -f Dockerfile ]; then
        echo "Dockerfile not found in $(pwd)"
        exit 1
    fi

    docker build -t notes-app .
    docker run -d -p 8000:80 notes-app:latest
}

echo "************* DEPLOYMENT STARTED *************"

code_clone
install_requirements
required_restarts
deploy

echo "************** DEPLOYMENT DONE ***************"
