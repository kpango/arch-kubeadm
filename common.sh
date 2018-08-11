#!/bin/sh
sudo systemctl stop firewalld;
sudo systemctl disable firewalld;
sudo echo 'overlay2' >> /etc/modules-load.d/overlay2.conf
sudo modprobe overlay2

sudo swapoff --all

sudo sed -i -e 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
sudo set enforce 0
sudo groupadd nogroup
sudo groupadd docker

sudo sed -i -e 's/Defaults    requiretty/#Defaults    requiretty/g' /etc/sudoers

sudo systemctl stop dnsmasq
sudo systemctl disable dnsmasq

sudo ntptime
sudo adjtimex -p
sudo timedatectl

curl https://get.docker.com > /tmp/install.sh
chmod +x /tmp/install.sh
sudo /tmp/install.sh

sudo mkdir -p /etc/systemd/system/docker.service.d
sudo cat <<EOF >! /etc/systemd/system/docker.service.d/override.conf
[Service]
ExecStart=/usr/bin/dockerd --storage-driver=overlay2
EOF

sudo systemctl daemon-reload
sudo systemctl start docker
sudo systemctl enable docker

yay -Sy kubectl-bin kubeadm-bin kubelet-bin kubectx
sudo systemctl enable kubelet
sudo systemctl start kubelet

sudo cat <<EOF >!  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sudo sysctl --system

sudo sed -i -e '9i Environment="KUBELET_EXTRA_ARGS=--feature-gates=DevicePlugins=true"' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

sudo systemctl daemon-reload
sudo systemctl restart kubelet

sudo /sbin/sysctl -w net.ipv4.ip_forward=1
sudo kubeadm reset

LB_IP="10.0.0.100"
LB_PORT="6443"
K8S_VERSION="v.1.11.0"
MASTER01_IP="10.0.0.2"
MASTER_HOSTNAME="master01"

sudo cat >kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1alpha2
kind: MasterConfiguration
kubernetesVersion: "$K8S_VERSION"
apiServerExtraArgs:
  apiserver-count: "5"
apiServerCertSANs:
- "$LB_IP"
api:
    controlPlaneEndpoint: "$LB_IP:$LB_PORT"
etcd:
  local:
    extraArgs:
      listen-client-urls: "https://127.0.0.1:2379,https://$MASTER01_IP:2379"
      advertise-client-urls: "https://$MASTER01_IP:2379"
      listen-peer-urls: "https://$MASTER01_IP:2380"
      initial-advertise-peer-urls: "https://$MASTER01_IP:2380"
      initial-cluster: "$MASTER01_HOSTNAME=https://$MASTER01_IP:2380"
    serverCertSANs:
      - $MASTER01_HOSTNAME
      - $MASTER01_IP
    peerCertSANs:
      - $MASTER01_HOSTNAME
      - $MASTER01_IP
networking:
    # This CIDR is a Calico
    # podSubnet: "192.168.0.0/16"
    # This CIDR is a Canal default. Substitute or remove for your CNI provider.
    podSubnet: "10.244.0.0/16"
EOF

sudo kubeadm init --config kubeadm-config.yaml
