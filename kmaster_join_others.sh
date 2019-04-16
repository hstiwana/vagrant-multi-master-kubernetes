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
kubeadm config images pull --kubernetes-version ${K8S_VERSION}

echo "[TASK 2] Copy Kubernetes Cluster config and certs from ${CONTROLLER1_IP} [Master1]"
mkdir -p /etc/kubernetes/pki/etcd 2>/dev/null
sshpass -p ${rootpwd} scp  ${opts} -qpr ${CONTROLLER1_IP}:/etc/kubernetes/admin.conf /etc/kubernetes/ 2>/dev/null
for pkiFiles in ca.crt ca.key sa.key sa.pub front-proxy-ca.crt front-proxy-ca.key
do
	sshpass -p ${rootpwd} scp  ${opts} -qpr ${CONTROLLER1_IP}:/etc/kubernetes/pki/${pkiFiles} /etc/kubernetes/pki/ 2>/dev/null
done

for etcdFiles in ca.crt ca.key
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

echo "[TASK 4] Setting up a Kube API healthz probe via NGINX"
cat >/etc/yum.repos.d/nginx.repo<<EOF
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=0
enabled=1
EOF

yes|yum -d0 -q -y install nginx

cat > /etc/nginx/conf.d/kubernetes.default.svc.cluster.local.conf << EOF
server {
  listen      80;
  server_name kubernetes.default.svc.cluster.local;

  location /healthz {
     proxy_pass                    https://${MY_IP}:6443/healthz;
     proxy_ssl_trusted_certificate /etc/kubernetes/pki/ca.crt;
  }
}
EOF

systemctl enable --now nginx
systemctl restart nginx

echo
curl -H "Host: kubernetes.default.svc.cluster.local" http://127.0.0.1/healthz;echo; echo

# Remove eth0 and setup gateway to our public network ${public_gw}/24
# This is needed for internet connectivity to work
# echo "[TASK 7] remove gateway to ${private_gw}"
# pub_net

# Copy Kube admin config
echo "[TASK 5] Copy kube admin config to Vagrant user .kube directory"
mkdir /home/vagrant/.kube 2>/dev/null
cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
mkdir /root/.kube 2>/dev/null
cp -f /etc/kubernetes/admin.conf /root/.kube/config

echo "[TASK 6] Fix kube-apiserver IP in /etc/kubernetes/manifests/kube-apiserver.yaml file"
sed -i "s/${CONTROLLER1_IP}/${MY_IP}/g" /etc/kubernetes/manifests/kube-apiserver.yaml
echo " ... done"
sleep 5
kubectl get all --all-namespaces
