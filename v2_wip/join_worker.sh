#!/bin/bash
source /vagrant/source_in_all.sh
head -3 /etc/hosts >/etc/hosts_new
cp -f /etc/hosts_new /etc/hosts
cat >>/etc/hosts<<EOF
$etchosts
EOF

# Remove eth0 and setup gateway
echo "[TASK 1] set gateway to ${nat_gw}"
nat_net

# Join worker nodes to the Kubernetes cluster
echo "[TASK 2] Join node to Kubernetes Cluster"
systemctl enable kubelet.service
sshpass -p ${rootpwd} scp ${opts} ${CONTROLLER1_IP}:/joincluster.sh /joincluster.sh
pri_net
bash /joincluster.sh 
rm /joincluster.sh
nat_net
