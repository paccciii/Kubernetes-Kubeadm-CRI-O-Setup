#!/bin/bash

# Step 1: Disable swap
sudo swapoff -a
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

# Step 2: Update apt repositories
sudo apt-get update -y

# Step 3: Load kernel modules and configure sysctl params
echo "overlay" | sudo tee /etc/modules-load.d/k8s.conf
echo "br_netfilter" | sudo tee -a /etc/modules-load.d/k8s.conf
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Step 4: Install CRI-O Runtime
OS="xUbuntu_22.04"
VERSION="1.28"

echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list



echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list


curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -

sudo apt-get update
sudo apt-get install cri-o cri-o-runc -y

sudo systemctl daemon-reload
sudo systemctl enable crio --now

# Step 5: Install Kubeadm & Kubelet & Kubectl
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

echo "$(curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key)" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-28-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-1-28-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes-1.28.list

echo "$(curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key)" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-29-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-1-29-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes-1.29.list

sudo apt-get update -y
sudo apt-get install -y kubelet="1.29.0-1.1" kubectl="1.29.0-1.1" kubeadm="1.29.0-1.1"
sudo apt-get update -y
sudo apt-mark hold kubelet kubeadm kubectl

# Step 6: Install jq and configure KUBELET_EXTRA_ARGS
sudo apt-get install -y jq

sudo sh -c 'local_ip="$(ip --json addr show eth0 | jq -r .[0].addr_info[] | grep "\"family\":\"inet\"" | cut -d "\"" -f 4)"; echo "KUBELET_EXTRA_ARGS=--node-ip=$local_ip" > /etc/default/kubelet'

# Step 7: Initialize Kubeadm On Master Node To Setup Control Plane
IPADDR="$(ip addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1)"
NODENAME=$(hostname -s)
POD_CIDR="192.168.0.0/16"

sudo kubeadm init --apiserver-advertise-address=$IPADDR  --apiserver-cert-extra-sans=$IPADDR  --pod-network-cidr=$POD_CIDR --node-name=$NODENAME
