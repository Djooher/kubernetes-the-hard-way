#!/bin/bash

set -e

echo "Updating system..."
sudo apt update && sudo apt upgrade -y

echo "Installing containerd..."
sudo apt install -y containerd

echo "Enabling kubelet..."
sudo systemctl enable kubelet
sudo systemctl start kubelet

echo "Setup complete."
