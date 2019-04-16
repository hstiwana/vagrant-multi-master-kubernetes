#!/bin/bash
source /vagrant/source_in_all.sh

# Enable ssh password authentication
echo "[TASK 1] Enable ssh password authentication"
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl reload sshd
systemctl disable --now NetworkManager.service NetworkManager-wait-online.service

# Set Root password
echo "[TASK 2] Set root password"
echo ${rootpwd} | passwd --stdin root >/dev/null 2>&1

# Remove eth0 and setup gateway
echo "[TASK 3] Update gateway to ${public_gw} for installations to work"
#call pub_net function from sourced script
yum -d0 -q -y install net-tools vim lsof
pub_net

# Update hosts file
echo "[TASK 4] Update /etc/hosts file"
cat >>/etc/hosts<<EOF
$etchosts
EOF

# Install docker from Docker-ce repository
echo "[TASK 5] Install docker container engine and sshpass"
yum install -d0 -y -q wget curl sshpass yum-utils device-mapper-persistent-data lvm2 
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 
yes|yum install -d0 -y -q docker-${docker_ver} 

#### Create /etc/docker directory.
mkdir /etc/docker 2>/dev/null

### Setup daemon.
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
mkdir -p /etc/systemd/system/docker.service.d >/dev/null 2>&1

# Enable docker service
echo "[TASK 6] Enable and start docker service"
systemctl daemon-reload
systemctl enable --now  docker >/dev/null 2>&1
systemctl restart docker

# Disable SELinux
echo "[TASK 7] Set SELinux in permissive mode (effectively disabling it)"
setenforce 0
sed -i --follow-symlinks 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Stop and disable firewalld
echo "[TASK 8] Stop and Disable firewalld"
systemctl disable firewalld >/dev/null 2>&1
systemctl stop firewalld

# Add sysctl settings
echo "[TASK 9] Add sysctl settings"
cat >/etc/sysctl.d/k8s.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system >/dev/null 2>&1

# Disable swap
echo "[TASK 10] Disable and turn off SWAP"
sed -i '/swap/d' /etc/fstab
swapoff -a

# Add yum repo file for Kubernetes
echo "[TASK 11] Add yum repo file for kubernetes"
cat >/etc/yum.repos.d/kubernetes.repo<<EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
        https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

# Install Kubernetes
echo "[TASK 12] Install Kubernetes (kubeadm, kubelet and kubectl)"
yum install -d0 -y -q kubeadm-${k8s_rpm_ver} kubelet-${k8s_rpm_ver} kubectl-${k8s_rpm_ver} kubernetes-cni-${cni_ver} 
systemctl enable kubelet.service >/dev/null 2>&1

# Update vagrant user's bashrc file
echo "[TASK 13] Update /etc/bashrc file"
echo "export TERM=xterm" >> /etc/bashrc
# echo "source <(kubectl completion bash)" >> /etc/bashrc
if [ $(grep kubectl /etc/bashrc|wc -l) != 1 ]; then 
	sudo su - -c "echo 'source <(kubectl completion bash)' >> /etc/bashrc"; 
  else 
	echo "Entry Found"; 
fi

echo "[TASK 14] Add entry in /etc/rc.local to ensure correct routes"
chmod +x /etc/rc.d/rc.local
cat >/etc/rc.local<<EOFL
#!/bin/bash
# THIS FILE IS ADDED FOR COMPATIBILITY PURPOSES
#
# It is highly advisable to create own systemd services or udev rules
# to run scripts during boot instead of using this file.
#
# In contrast to previous versions due to parallel execution during boot
# this script will NOT be run after all other services.
#
# Please note that you must run 'chmod +x /etc/rc.d/rc.local' to ensure
# that this script will be executed during boot.

touch /var/lock/subsys/local
# Remove eth0 and setup gateway
echo "[ CONFIG TASK ] Update gateway to ${public_gw} for configurations to work"
route -n | awk '{ if (\$8 =="eth0" && \$2 != "0.0.0.0") print "route del default gw " \$2; }'|bash -s 
route delete default gw ${private_gw} > /dev/null 2>&1
route add default gw ${public_gw} > /dev/null 2>&1
route -A inet6 add default gw fc00::1 ${public_eth} > /dev/null 2>&1
EOFL

if [ ${MY_HOSTNAME} == ${LPLB} ];then
pub_net
echo "[TASK 16] Install Nginx to configure as LB"
cat >/etc/yum.repos.d/nginx.repo<<EOF
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=0
enabled=1
EOF

# Install Nginx
yes|yum -d0 -q -y install nginx
echo "[TASK 17] Setting up a Kube API Frontend Load Balancer with NGINX"
mkdir -p /etc/nginx/tcpconf.d
if [ $(grep tcpconf.d /etc/nginx/nginx.conf|wc -l) != 1 ]; then
        sudo su - -c "echo 'include /etc/nginx/tcpconf.d/*;' >> /etc/nginx/nginx.conf";
else
        echo "Entry Found";
fi
# Create cluster with 1 node in LB
cat >/etc/nginx/tcpconf.d/kubernetes.conf<<EOF
stream {
    upstream kubernetes {
        server $CONTROLLER1_IP:6443;
    }

    server {
        listen 6443;
        listen 443;
        proxy_pass kubernetes;
    }

}
EOF

systemctl enable --now nginx
systemctl restart nginx
mkdir /kube
# 1. kubeadm init config template
echo '[TASK 1. kubeadm init config template]'
export KUBEADM_TOKEN=$(kubeadm token generate)
cat >/kube/kubeadm-init-config.tmpl.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta1
kind: InitConfiguration
bootstrapTokens:
- token: "${KUBEADM_TOKEN}"
  description: "default kubeadm bootstrap token"
  ttl: "0"
localAPIEndpoint:
  advertiseAddress: ${K8S_API_ADDVERTISE_IP_1}
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
kubernetesVersion: v${K8S_VERSION}
clusterName: ${K8S_CLUSTER_NAME}
controlPlaneEndpoint: ${controlPlaneEndpoint}
certificatesDir: ${LOCAL_CERTS_DIR}
networking:
  podSubnet: ${podSubnet}
apiServer:
  certSANs:
  - ${K8S_API_ENDPOINT_INTERNAL}
  - ${K8S_API_ENDPOINT}
  - ${PLBIP}
  - ${PUB_HOST}
  - ${PUB_IP}
  # https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/
  extraArgs:
    advertise-address: ${K8S_API_ADDVERTISE_IP_1}
    bind-address: ${K8S_API_ADDVERTISE_IP_1}
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
EOF
# 3. Input Parameters

echo '[TASK 2. Input Parameters]'
# export addresses and other vars
set -a
K8S_API_ENDPOINT=${K8S_API_ENDPOINT}
K8S_VERSION=${K8S_VERSION}
K8S_CLUSTER_NAME=${K8S_CLUSTER_NAME}
OUTPUT_DIR=${OUTPUT_DIR}
LOCAL_CERTS_DIR=${LOCAL_CERTS_DIR}
KUBECONFIG=${KUBECONFIG}
mkdir -p ${OUTPUT_DIR}
MASTER_SSH_ADDR_1=${MASTER_SSH_ADDR_1}
set +a

# 4. Generating kubeadm token
# 5. Applying parameters to the template
echo '[TASK 3/4. Generating kubeadm token]'
envsubst < /kube/kubeadm-init-config.tmpl.yaml > ${OUTPUT_DIR}/kubeadm-init-config.yaml

# 6. Generate Certificates
echo '[TASK 5. Generate Certificates]'
kubeadm init phase certs all --config ${OUTPUT_DIR}/kubeadm-init-config.yaml

# 2. kubeadm join template
echo '[TASK 6. kubeadm join template]'
export CA_CERT_HASH=$(openssl x509 -pubkey -in ${LOCAL_CERTS_DIR}/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* /sha256:/')

cat >/kube/kubeadm-join-config.tmpl.yaml<<EOF
apiVersion: kubeadm.k8s.io/v1beta1
kind: JoinConfiguration
nodeRegistration:
  kubeletExtraArgs:
    enable-controller-attach-detach: "false"
    node-labels: "node-type=vm"
discovery:
  bootstrapToken:
    apiServerEndpoint: ${controlPlaneEndpoint}
    token: ${KUBEADM_TOKEN}
    caCertHashes:
    - ${CA_CERT_HASH}
EOF
envsubst < /kube/kubeadm-join-config.tmpl.yaml > ${OUTPUT_DIR}/kubeadm-join-config.yaml

# 7. Generate CA Certificate Hash
echo '[TASK 7. Generate CA Certificate Hash]'
export CERTS_DIR=${1:-$LOCAL_CERTS_DIR}
export CA="${CERTS_DIR}"/ca.crt
export CA_KEY="${CERTS_DIR}"/ca.key

if [[ ! -f ${CA} || ! -f ${CA_KEY} ]]; then
   echo "Error: CA files ${CA}  ${CA_KEY} are missing "
   exit 1
fi

export CLIENT_SUBJECT=${CLIENT_SUBJECT:-"/O=system:masters/CN=kubernetes-admin"}
export CLIENT_CSR=${CERTS_DIR}/kubeadmin.csr
export CLIENT_CERT=${CERTS_DIR}/kubeadmin.crt
export CLIENT_KEY=${CERTS_DIR}/kubeadmin.key
export CLIENT_CERT_EXTENSION=${CERTS_DIR}/cert-extension

# We need faketime for cases when your client time is on UTC+
## which faketime >/dev/null 2>&1
## if [[ $? == 0 ]]; then
##   OPENSSL="faketime -f -1d openssl"
## else
##   echo "Warning, faketime is missing, you might have a problem if your server time is less tehn"
  OPENSSL=openssl
## fi

echo "OPENSSL = $OPENSSL "
echo "Creating Client KEY $CLIENT_KEY "
$OPENSSL genrsa -out "$CLIENT_KEY" 2048

echo "Creating Client CSR $CLIENT_CSR "
$OPENSSL req -subj "${CLIENT_SUBJECT}" -sha256 -new -key "${CLIENT_KEY}" -out "${CLIENT_CSR}"

echo "--- create  ca extfile"
echo "extendedKeyUsage=clientAuth" > "$CLIENT_CERT_EXTENSION"

echo "--- sign  certificate ${CLIENT_CERT} "
$OPENSSL x509 -req -days 1096 -sha256 -in "$CLIENT_CSR" -CA "$CA" -CAkey "$CA_KEY" \
-CAcreateserial -out "$CLIENT_CERT" -extfile "$CLIENT_CERT_EXTENSION" -passin pass:"$CA_PASS"

# 8. Generate kubeconfig for accessing cluster by public k8s endpoint
echo '[TASK 8. Generate kubeconfig for accessing cluster by public k8s endpoint]'
# Set variables based on cert values
set -a
export CLIENT_CERT_B64=$(base64 -w0  < $LOCAL_CERTS_DIR/kubeadmin.crt)
export CLIENT_KEY_B64=$(base64 -w0  < $LOCAL_CERTS_DIR/kubeadmin.key)
export CA_DATA_B64=$(base64 -w0  < $LOCAL_CERTS_DIR/ca.crt)
set +a

cat >/kube/kubeconfig-template.yaml<<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${CA_DATA_B64}
    server: https://${K8S_API_ENDPOINT}:6443
  name: ${K8S_CLUSTER_NAME}
contexts:
- context:
    cluster: ${K8S_CLUSTER_NAME}
    user: ${K8S_CLUSTER_NAME}-admin
    namespace: default
  name: ${K8S_CLUSTER_NAME}
current-context: ${K8S_CLUSTER_NAME}
kind: Config
preferences: {}
users:
- name: ${K8S_CLUSTER_NAME}-admin
  user:
    client-certificate-data: ${CLIENT_CERT_B64}
    client-key-data: ${CLIENT_KEY_B64}
EOF

#execute template to KUBECONFIG=${OUTPUT_DIR}/kubeconfig
envsubst < /kube/kubeconfig-template.yaml > ${OUTPUT_DIR}/kubeconfig

# 9. Install prerequisites on master
echo '[TASK 9. Install prerequisites on master]'
# We have already done this as part of bootstrap_new.sh script 
# so next line is commented out, otherwise we will have to write a script 
# to install "docker, kubelet, kubeadmin, kubectl"
# ssh ${MASTER_SSH_ADDR_1} 'sudo bash -s' < ${OUTPUT_DIR}/prepare-master.sh

# 10. Copy certificates to the master
echo '[10. Copy certificates to the master]'

cat /etc/hosts | sshpass -p ${rootpwd} ssh ${opts} -qt "${MASTER_SSH_ADDR_1}" 'sudo dd of=/etc/hosts'
tar -cz --directory=${LOCAL_CERTS_DIR} . | sshpass -p ${rootpwd} ssh ${opts} -qt "${MASTER_SSH_ADDR_1}" 'sudo mkdir -p /etc/kubernetes/pki; sudo tar -xz --directory=/etc/kubernetes/pki/'

# 11. Copy kubeadm config file to the master
echo '[TASK 11. Copy kubeadm config file to the master]'
sed '/certificatesDir:/d' ${OUTPUT_DIR}/kubeadm-init-config.yaml | sshpass -p ${rootpwd} ssh ${opts} -qt "${MASTER_SSH_ADDR_1}" 'sudo dd of=/root/kubeadm-init-config.yaml'

# 12. Run kubeadm init without certs phase
sshpass -p ${rootpwd} ssh ${opts} -qt "${MASTER_SSH_ADDR_1}" '/vagrant/kmaster_nginx.sh'
echo '[TASK 12. Run kubeadm init without certs phase]'
sshpass -p ${rootpwd} ssh ${opts} -qt "${MASTER_SSH_ADDR_1}" "kubeadm init --skip-phases certs ${kubeadminitopts} --config /root/kubeadm-init-config.yaml |tee -a kubeadm-init.logs"
sshpass -p ${rootpwd} ssh ${opts} -qt "${MASTER_SSH_ADDR_1}" '/vagrant/kmaster_create_join_commands.sh'

 
# 13 Ensure that it is running
echo '[TASK 13. Ensure that it is running]'
export KUBECONFIG=$OUTPUT_DIR/kubeconfig
kubectl get pods --all-namespaces

# 14. Installing Pod Network
echo '[TASK 14. Installing Pod Network]'
#curl -s --output $OUTPUT_DIR/kube-flannel.yaml https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml
#kubectl apply -f $OUTPUT_DIR/kube-flannel.yaml
kubectl apply -f /vagrant/kube-flannel.yaml
echo "CHECK: sleep 20"
sleep 20
echo "CHECK: kubectl get nodes"
kubectl get nodes 

# 15. Run kubeadm join on other master nodes
echo '[TASK 15. Run kubeadm join on other master nodes]'
for MSTR in ${MST2} ${MST3}
do
       	echo "[BOOTSTRAP TASK MASTER Join] Joining ${MSTR} in K8s Cluster"
	sshpass -p ${rootpwd} ssh ${opts} -qt "${MSTR}" '/vagrant/kmaster_join_others.sh'
        echo "sleep 20"
	sleep 20
done

# 16. Joining Nodes
for WORKER in ${WKR1} ${WKR2} ${WKR3}
do
       echo "[BOOTSTRAP TASK Node Join] Joining ${WORKER} in K8s Cluster"
       cat /etc/hosts | sshpass -p ${rootpwd} ssh ${opts} -qt "${WORKER}" 'sudo dd of=/etc/hosts'
       #cat ${OUTPUT_DIR}/kubeadm-join-config.yaml | sshpass -p ${rootpwd} ssh ${opts} -qt "${WORKER}" 'dd of=/root/kubeadm-join-config.yaml'
        sshpass -p ${rootpwd} ssh ${opts} -qt "${WORKER}" '/vagrant/join_worker.sh'
       echo
       echo
       echo "######### [DONE] ----> [BOOTSTRAP TASK Node Join] Joined K8S Cluster as ${WORKER} ###########"

done
# Update Cluster LB with 2 more nodes
cat >/etc/nginx/tcpconf.d/kubernetes.conf<<EOF
stream {
    upstream kubernetes {
        server $CONTROLLER1_IP:6443;
        server $CONTROLLER2_IP:6443;
        server $CONTROLLER3_IP:6443;
    }

    server {
        listen 6443;
        listen 443;
        proxy_pass kubernetes;
    }

}
EOF
systemctl restart nginx.service
fi 
#END of MY_HOSTNAME LPLB IF Statement
