#!/bin/bash
source /vagrant/source_in_all.sh

curl -H "Host: kubernetes.default.svc.cluster.local" -i http://127.0.0.1/healthz

mkdir /home/vagrant/.kube 2>/dev/null
cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
mkdir /root/.kube 2>/dev/null
cp -f /etc/kubernetes/admin.conf /root/.kube/config

# Generate Cluster join command
echo "[MASTER 1 TASK - FINAL] Generate and save cluster join command to /joincluster.sh"
rm -rf /joincluster.sh > /dev/null 2>&1
kubeadm token create --print-join-command --kubeconfig=${kubeconfig} > /joincluster.sh

master=$(cat /joincluster.sh)
echo "${master} --experimental-control-plane ${kubeadminitopts}" >/joinMaster.sh
