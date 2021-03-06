#!/bin/bash
source /vagrant/source_in_all.sh
head -3 /etc/hosts >/etc/hosts_new
cp -f /etc/hosts_new /etc/hosts
cat >>/etc/hosts<<EOF
$etchosts
EOF

# Initialize Kubernetes Masters

systemctl enable kubelet.service
# Download required images first
echo "[TASK 1 - PRE-Flight-TASK] kubeadm config images pull"
kubeadm config images pull --kubernetes-version ${K8S_VERSION} 2>/dev/null

echo "[TASK 2] Copy Kubernetes Cluster config and certs from ${CONTROLLER1_IP} [Master1]"
mkdir -p /etc/kubernetes/pki/etcd 2>/dev/null
sshpass -p ${rootpwd} scp  ${opts} -qpr ${CONTROLLER1_IP}:/etc/kubernetes/admin.conf /etc/kubernetes/ 2>/dev/null
for pkiFiles in ca.crt ca.key sa.key sa.pub front-proxy-ca.crt front-proxy-ca.key
do
	sshpass -p ${rootpwd} scp  ${opts} -qpr ${CONTROLLER1_IP}:/etc/kubernetes/pki/${pkiFiles} /etc/kubernetes/pki/ 2>/dev/null
done

for etcdFiles in ca.crt ca.key etcd_encryption_config.yaml
do
	sshpass -p ${rootpwd} scp  ${opts} -qpr ${CONTROLLER1_IP}:/etc/kubernetes/pki/etcd/${etcdFiles} /etc/kubernetes/pki/etcd/ 2>/dev/null
done

#******** Setup gateway to ${private_gw} so that kubeadmin can pickup right address for API service
# echo "[TASK 5] set gateway to ${private_gw}"
# pri_net

echo "[TASK 3] Join cluster using kubeadmin"
sshpass -p ${rootpwd} scp ${opts} ${CONTROLLER1_IP}:/joinMaster.sh /joinMaster.sh
bash /joinMaster.sh
rm /joinMaster.sh

# Remove eth0 and setup gateway to our public network ${public_gw}/24
# This is needed for internet connectivity to work
# echo "[TASK 7] remove gateway to ${private_gw}"
# pub_net

# Copy Kube admin config
echo "[TASK 4] Copy kube admin config to Vagrant user .kube directory"
mkdir /home/vagrant/.kube 2>/dev/null
cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
mkdir /root/.kube 2>/dev/null
cp -f /etc/kubernetes/admin.conf /root/.kube/config

echo "[TASK 5] Fix kube-apiserver IP and ETCD cluster node IPs"
export bad_ip=$(echo ${public_gw}|cut -d. -f1-3)
export good_ip=$(echo ${private_gw}|cut -d. -f1-3)

sed -i "s/${CONTROLLER1_IP}/${MY_IP}/g" /etc/kubernetes/manifests/kube-apiserver.yaml
sed -i "s/${bad_ip}/${good_ip}/g" /etc/kubernetes/manifests/etcd.yaml
sed -i "s/${bad_ip}/${good_ip}/g" /etc/kubernetes/manifests/kube-apiserver.yaml
echo " ... done"
sleep 10

kubectl get all --all-namespaces --kubeconfig=/etc/kubernetes/admin.conf
