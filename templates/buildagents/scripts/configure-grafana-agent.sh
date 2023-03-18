#!/bin/bash

mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt-get update
sudo apt-get install grafana-agent

sudo cp /imagegeneration/grafana-agent.yaml /etc/grafana-agent.yaml -f

sudo systemctl enable grafana-agent.service
sudo systemctl start grafana-agent