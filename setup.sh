#!/bin/bash

set -e

echo " Updating system packages..."
sudo apt update -y
sudo apt upgrade -y

echo "🔧 Installing basic dependencies..."
sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release

echo " Installing container runtime (containerd)..."
sudo apt install -y containerd

echo "⚙️ Configuring containerd..."
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

echo "🔄 Restarting containerd..."
sudo systemctl restart containerd
sudo systemctl enable containerd

echo "📡 Enabling kernel modules for Kubernetes..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

echo "🌐 Setting sysctl params..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF

sudo sysctl --system

echo " Basic Kubernetes node setup completed!"
