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
echo "source /vagrant/source_in_all.sh" > /joincluster.sh
echo "pri_net" >>/joincluster.sh
kubeadm token create --print-join-command --kubeconfig=${kubeconfig} >> /joincluster.sh 2>/dev/null
echo "pub_net" >>/joincluster.sh

sed 's/:6443/:6443 --control-plane --ignore-preflight-errors=all /' /joincluster.sh >/joinMaster.sh
sed 's/.$/ 2>\/dev\/null/g' /joinMaster.sh
