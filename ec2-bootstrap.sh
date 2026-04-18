#!/bin/bash

# 1. Get IP address (IMDSv2)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INTERNAL_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Install basic dependencies first
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo mkdir -p -m 0755 /etc/apt/keyrings

# --- FIX: DOWNLOAD BOTH KEYS BEFORE DOING APT UPDATE ---

# Download Kubernetes Key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Download Docker Key
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# --- END FIX ---

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Handle Trixie/Bookworm logic
VERSION_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
[ "$VERSION_CODENAME" = "trixie" ] && REPO_CODENAME="bookworm" || REPO_CODENAME=$VERSION_CODENAME

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $REPO_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update

sudo apt-get install -y kubelet kubeadm kubectl

sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable --now kubelet

#systemctl status kubelet

##############################
#kernel parameter modification

cat <<EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo modprobe br_netfilter

######### Important notes modprobe doesnt persistent across reboot ###################

######### To presistent across reboot we need to add in the /etc/load-modules.d/k8.conf ##########

cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF

sysctl -p /etc/sysctl.d/kubernetes.conf

######INSTALL CRI#######

####### INSTALL CRI (Containerd) #######

# 1. Ensure the directory exists
sudo mkdir -p -m 0755 /etc/apt/keyrings

# 2. Download the GPG key correctly
# We use 'debian' specifically, and we'll ensure the path is correct
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 3. Handle the 'Trixie' (Debian 13) repo issue
# Docker doesn't always have a 'trixie' folder immediately.
# If 'trixie' fails, we fallback to 'bookworm' (Debian 12) which is stable and compatible.
VERSION_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
if [ "$VERSION_CODENAME" = "trixie" ]; then
    REPO_CODENAME="bookworm"
else
    REPO_CODENAME=$VERSION_CODENAME
fi

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian \
$REPO_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Install Containerd
sudo apt-get update
sudo apt-get install -y containerd.io

# 5. Configure Containerd for Kubernetes
sudo mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd



#### subjective need to change according to your device ##########

sudo swapoff -a


sudo apt update
sudo apt install -y containerd.io
systemctl restart containerd.service

#######Kubeadm setup for kube-system components installations####

kubeadm init --apiserver-advertise-address $INTERNAL_IP --pod-network-cidr "10.244.0.0/16" --upload-certs




mkdir -p /root/.kube
sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
sudo chown $(id -u):$(id -g) /root/.kube/config

echo "alias k=kubectl 
export KUBECONFIG=/etc/kubernetes/admin.conf" >> /root/.bashrc


#Network CNI

kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

#add this argument in flannel or CNI daemonset for persistent across reboot
#args:
#- --ip-masq
#- --kube-subnet-mgr
#- --iface=enp0s3      # add this line


#### LoadBalancer ########


### Helm Install ###
#wget -P /root/ https://get.helm.sh/helm-v4.1.3-linux-amd64.tar.gz
#tar -xvf /root/helm-v4.1.3-linux-amd64.tar.gz -C /root
#mv /root/linux-amd64/helm /usr/local/bin/

### Helm Repo for Ingress Nginx Loadbalancer #####
#helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
#helm install ingress-nginx ingress-nginx/ingress-nginx
