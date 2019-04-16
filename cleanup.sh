#!/bin/bash
yes|kubeadm reset
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
systemctl stop kubelet 2>/dev/null;
docker rm -f $(docker ps -q) 2>/dev/null; mount | grep "/var/lib/kubelet/*" | awk '{print $3}' | xargs umount 1>/dev/null 2>/dev/null;
rm -rf /kube /root/kubeadm* /var/lib/kubelet /etc/kubernetes /var/lib/etcd /etc/cni /etc/kubernetes /etc/systemd/system/kubelet.service.d/20-etcd-service-manager.conf 2>/dev/null;
mkdir -p /etc/kubernetes 2>/dev/null
ip link set cbr0 down 2>/dev/null; ip link del cbr0 2>/dev/null;
ip link set cni0 down 2>/dev/null; ip link del cni0 2>/dev/null;
ip link set flannel.1 down 2>/dev/null; ip link del flannel.1 2>/dev/null;
head -3 /etc/hosts >/etc/hosts_new
cp -f /etc/hosts_new /etc/hosts
rm -rf .kube/config /ktmp 2>/dev/null
systemctl daemon-reload
systemctl start kubelet
systemctl restart docker
