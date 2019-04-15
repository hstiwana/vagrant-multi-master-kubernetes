#!/bin/bash
source /vagrant/source_in_all.sh
head -3 /etc/hosts >/etc/hosts_new
cp -f /etc/hosts_new /etc/hosts
cat >>/etc/hosts<<EOF
$etchosts
EOF

# Download required images first
pub_net
echo "[PRE-Flight-TASK] kubeadm config images pull"
kubeadm config images pull --kubernetes-version ${pods_ver}

echo "[TASK 1] Setting up a Kube API healthz probe via NGINX"
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
     proxy_pass                    https://127.0.0.1:6443/healthz;
     proxy_ssl_trusted_certificate /etc/kubernetes/pki/ca.crt;
  }
}
EOF

systemctl enable --now nginx
systemctl enable kubelet.service

#pri_net

###### trying based on https://medium.com/velotio-perspectives/demystifying-high-availability-in-kubernetes-using-kubeadm-3d83ed8c458b
#echo "[TASK 2] Setup load balancer for API Services"
#yum -d0 -q -y install keepalived
#cat >/etc/keepalived/keepalived.conf<<EOF
#! Configuration File for keepalived
#global_defs {
#  router_id LVS_DEVEL
#}
#
#vrrp_script check_apiserver {
#  script "/etc/keepalived/check_apiserver.sh"
#  interval 3
#  weight -2
#  fall 10
#  rise 2
#}
#
#vrrp_instance VI_1 {
#    state MASTER
#    interface ${private_eth}
#    virtual_router_id 51
#    priority 110
#    authentication {
#        auth_type PASS
#        auth_pass whatwasthepassword
#    }
#    virtual_ipaddress {
#        ${ETCD_VIP}
#    }
#    track_script {
#        check_apiserver
#    }
#}
#EOF
#
#cat >/etc/keepalived/check_apiserver.sh<<EOF
##!/bin/sh
#
#errorExit() {
#    echo "*** $*" 1>&2
#    exit 1
#}
#
#curl --silent --max-time 2 --insecure https://localhost:6443/ -o /dev/null || errorExit "Error GET https://localhost:6443/"
#if ip addr | grep -q ${ETCD_VIP}; then
#    curl --silent --max-time 2 --insecure https://${ETCD_VIP}:6443/ -o /dev/null || errorExit "Error GET https://${ETCD_VIP}:6443/"
#fi
#EOF
#chmod +x /etc/keepalived/check_apiserver.sh
#systemctl enable --now keepalived

#rm /tmp/kubeadm-config-${MY_HOSTNAME}.yaml 2>/dev/null
#cat >/tmp/kubeadm-config-${MY_HOSTNAME}.yaml <<EOF
#apiVersion: kubeadm.k8s.io/v1beta1
#kind: ClusterConfiguration
#kubernetesVersion: ${pods_ver}
#controlPlaneEndpoint: ${controlPlaneEndpoint}
#Networking:
#  dnsDomain: ${dnsDomain}
#  serviceSubnet: ${serviceSubnet}
#  podSubnet: ${podSubnet}
#apiServer:
#    extraArgs:
#      advertise-address: ${CONTROLLER1_IP}
#      anonymous-auth: "true"
#      enable-admission-plugins: Initializers,NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota
#      audit-log-path: /var/log/api_audit.log
#    certSANs:
#      - 127.0.0.1
#      - ${CONTROLLER1_IP}
#      - ${CONTROLLER2_IP}
#      - ${CONTROLLER3_IP}
#      - ${LLBIP}
#      - ${PLBIP}
#      - ${LPLB}
#      - ${MST1}
#      - ${MST2}
#      - ${MST3}
#      - ${PUB_HOST}
#      - ${PUB_IP}
#etcd:
#    external:
#        endpoints:
#        - https://${CONTROLLER1_IP}:2379
#        - https://${CONTROLLER2_IP}:2379
#        - https://${CONTROLLER3_IP}:2379
#        caFile: /etc/kubernetes/pki/etcd/ca.crt
#        certFile: /etc/kubernetes/pki/apiserver-etcd-client.crt
#        keyFile: /etc/kubernetes/pki/apiserver-etcd-client.key
#EOF

export KUBEADM_TOKEN=$(kubeadm token generate)

rm ${LOCAL_CERTS_DIR}/kubeadm-config-${MY_HOSTNAME}.yaml 2>/dev/null
cat >${LOCAL_CERTS_DIR}/kubeadm-config-${MY_HOSTNAME}.yaml<<EOF
apiVersion: kubeadm.k8s.io/v1beta1
kind: InitConfiguration
bootstrapTokens:
- token: "${KUBEADM_TOKEN}"
  description: "default kubeadm bootstrap token"
  ttl: "0"
localAPIEndpoint:
  advertiseAddress: ${MY_IP}
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
kubernetesVersion: ${pods_ver}
clusterName: ${K8S_CLUSTER_NAME}
controlPlaneEndpoint: ${controlPlaneEndpoint}
Networking:
  dnsDomain: ${dnsDomain}
#  serviceSubnet: ${serviceSubnet}
  podSubnet: ${podSubnet}
apiServer:
  certSANs:
  - 127.0.0.1
  - ${CONTROLLER1_IP}
  - ${CONTROLLER2_IP}
  - ${CONTROLLER3_IP}
  - ${LLBIP}
  - ${PLBIP}
  - ${LPLB}
  - ${MST1}
  - ${MST2}
  - ${MST3}
  - ${PUB_HOST}
  - ${PUB_IP}
  # https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/
  extraArgs:
    max-requests-inflight: "1000"
    max-mutating-requests-inflight: "500"        
    default-watch-cache-size: "500"
    watch-cache-sizes: "persistentvolumeclaims#1000,persistentvolumes#1000"
controllerManager:
  # https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/
  extraArgs:
    deployment-controller-sync-period: "50s"
# scheduler:
#   # https://kubernetes.io/docs/reference/command-line-tools-reference/kube-scheduler/
#   extraArgs:
#     address: 0.0.0.0
etcd:
  external:
    endpoints:
    - https://${CONTROLLER1_IP}:2379
    - https://${CONTROLLER2_IP}:2379
    - https://${CONTROLLER3_IP}:2379
    caFile: /etc/kubernetes/pki/etcd/ca.crt
    certFile: /etc/kubernetes/pki/apiserver-etcd-client.crt
    keyFile: /etc/kubernetes/pki/apiserver-etcd-client.key
EOF
# Initialize the control plane

# Check ETCD Cluster status before exist.
if [ ${MY_HOSTNAME} == ${MST1} ]; then
        etcd_status
fi

pri_net

echo "[TASK 2.0] Initialize certificates " |tee -a /root/kubeinit.log
kubeadm init phase certs all --config ${LOCAL_CERTS_DIR}/kubeadm-config-${MY_HOSTNAME}.yaml >>/root/kubeinit.log
/vagrant/generate-admin-client-certs.sh >>/root/kubeinit.log
echo "[TASK 2.1] Initialize the control plane" |tee -a /root/kubeinit.log
kubeadm init --config=${LOCAL_CERTS_DIR}/kubeadm-config-${MY_HOSTNAME}.yaml ${kubeadminitopts} >> /root/kubeinit.log 2>&1
#kubeadm init --experimental-upload-certs --config=/vagrant/yaml/kubeadm-config-${MY_HOSTNAME}.yaml >> /root/kubeinit.log 2>/dev/null
pub_net
echo "[TASK 3] Copy kube admin config to Vagrant user .kube directory" 
mkdir /home/vagrant/.kube 2>/dev/null
cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
mkdir /root/.kube 2>/dev/null
cp -f /etc/kubernetes/admin.conf /root/.kube/config

# pub_net
# Deploy network
echo "[TASK 4] Deploy Network Plugin and check API nginx status"
su - vagrant -c "kubectl create -f /vagrant/yaml/${net_plugin}.yaml"

sleep 10
curl -k https://127.0.0.1:6443/healthz; echo 

# Generate Cluster join command
echo "[TASK 5] Generate and save cluster join command to /joincluster.sh"
rm -rf /joincluster.sh > /dev/null 2>&1
kubeadm token create --print-join-command --kubeconfig=${kubeconfig} > /joincluster.sh

master=$(cat /joincluster.sh)
# code for kubernetes v.1.14.0 onwards
#keyM=$(kubeadm init phase upload-certs --experimental-upload-certs |tail -1)
#echo "${master} --ignore-preflight-errors=all --experimental-control-plane --certificate-key ${keyM}" >/joinMaster.sh
echo "${master} ${kubeadminitopts}" >/joinMaster.sh
