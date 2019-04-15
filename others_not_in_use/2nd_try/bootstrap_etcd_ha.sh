#!/bin/bash

source /vagrant/source_in_all.sh

head -3 /etc/hosts >/etc/hosts_new
cp -f /etc/hosts_new /etc/hosts
cat >>/etc/hosts<<EOF
$etchosts
EOF

pub_net

# https://kubernetes.io/docs/setup/independent/setup-ha-etcd-with-kubeadm/
# Configure the kubelet to be a service manager for etcd
# Since etcd was created first, you must override the service priority by creating a new unit file that has higher precedence than the kubeadm-provided kubelet unit file.
echo "[ETCD HA TASK 0] Configure the kubelet to be a service manager for etcd"
mkdir /etc/systemd/system/kubelet.service.d 2>/dev/null

cat << EOF > /etc/systemd/system/kubelet.service.d/20-etcd-service-manager.conf
[Service]
ExecStart=
ExecStart=/usr/bin/kubelet --address=127.0.0.1 --pod-manifest-path=/etc/kubernetes/manifests --allow-privileged=true --cgroup-driver=systemd
Restart=always
EOF
# Let's copy kubelet kubeadm.conf too
# without this master node is not shown in "kubectl get nodes"
cp -pf cp   /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf /etc/systemd/system/kubelet.service.d/ 2>/dev/null
sed -i 's#Environment="KUBELET_KUBECONFIG_ARGS=-.*#Environment="KUBELET_KUBECONFIG_ARGS=--kubeconfig=/etc/kubernetes/kubelet.conf --require-kubeconfig=true --cgroup-driver=systemd"#g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

systemctl daemon-reload
systemctl restart kubelet


################################### ETCD HA Cluster #####################
## Run this code only on $MST1 ## 
kubeadmcfg(){
echo "[ETCD HA TASK 1] Create temp directories to store ETCD files and cert"
# Create temp directories to store files that will end up on other hosts.
mkdir -p /ktmp/${CONTROLLER1_IP}/ /ktmp/${CONTROLLER2_IP}/ /ktmp/${CONTROLLER3_IP}/

for i in "${!ETCDHOSTS[@]}"; do
HOST=${ETCDHOSTS[$i]}
NAME=${NAMES[$i]}
cat << EOF > /ktmp/${HOST}/kubeadmcfg.yaml
apiVersion: "kubeadm.k8s.io/v1beta1"
kind: ClusterConfiguration
etcd:
    local:
        serverCertSANs:
        - "${HOST}"
        - "${LPLB}"
        peerCertSANs:
        - "${HOST}"
        - "${LPLB}"
        extraArgs:
            initial-cluster: ${NAMES[0]}=https://${ETCDHOSTS[0]}:2380,${NAMES[1]}=https://${ETCDHOSTS[1]}:2380,${NAMES[2]}=https://${ETCDHOSTS[2]}:2380
            initial-cluster-state: new
            name: ${NAME}
            listen-peer-urls: https://${HOST}:2380
            listen-client-urls: https://${HOST}:2379
            advertise-client-urls: https://${HOST}:2379
            initial-advertise-peer-urls: https://${HOST}:2380
EOF
done
}

# Create CA cert if it is MASTER1 server
if [ ${MY_HOSTNAME} == ${MST1} ];then
  # Initialize Kubernetes
  echo "[ETCD HA TASK 2] Initialize [CA] for the [ETCD] Cluster"
  kubeadm init phase certs etcd-ca
  # Above command creates following two files
  # /etc/kubernetes/pki/etcd/ca.crt
  # /etc/kubernetes/pki/etcd/ca.key

else # If server is not First Master (kmaster1), copy certs from MASTER1
  mkdir -p /ktmp/ /etc/kubernetes/pki/etcd/ 2>/dev/null
  for CA_CERT in ca.crt ca.key
   do
    # sshpass -p ${rootpwd} ssh ${opts} -qt root@${MST1} '/vagrant/bootstrap_etcd_ha.sh'
    sshpass -p ${rootpwd} scp ${opts} -qpr root@${MST1}:/etc/kubernetes/pki/etcd/${CA_CERT} /etc/kubernetes/pki/etcd/${CA_CERT}
  done
fi

gen_etcd_certs(){ 
if [ ${MY_HOSTNAME} == ${MST3} ];then
   echo "[ETCD HA TASK 3] Create certificates for ${CONTROLLER3_IP}"
	kubeadm init phase certs etcd-server --config=/ktmp/${CONTROLLER3_IP}/kubeadmcfg.yaml 2>/dev/null
	kubeadm init phase certs etcd-peer --config=/ktmp/${CONTROLLER3_IP}/kubeadmcfg.yaml 2>/dev/null
	kubeadm init phase certs etcd-healthcheck-client --config=/ktmp/${CONTROLLER3_IP}/kubeadmcfg.yaml 2>/dev/null
	kubeadm init phase certs apiserver-etcd-client --config=/ktmp/${CONTROLLER3_IP}/kubeadmcfg.yaml 2>/dev/null
	# cleanup non-reusable certificates
	find /ktmp/${CONTROLLER2_IP} -name ca.key -type f -delete
    echo "[ETCD HA TASK - Done ] certs generated"

elif [ ${MY_HOSTNAME} == ${MST2} ];then
    echo "[ETCD HA TASK 3] Create certificates for ${CONTROLLER2_IP}"
	kubeadm init phase certs etcd-server --config=/ktmp/${CONTROLLER2_IP}/kubeadmcfg.yaml 2>/dev/null
	kubeadm init phase certs etcd-peer --config=/ktmp/${CONTROLLER2_IP}/kubeadmcfg.yaml 2>/dev/null
	kubeadm init phase certs etcd-healthcheck-client --config=/ktmp/${CONTROLLER2_IP}/kubeadmcfg.yaml 2>/dev/null
	kubeadm init phase certs apiserver-etcd-client --config=/ktmp/${CONTROLLER2_IP}/kubeadmcfg.yaml 2>/dev/null
	find /ktmp/${CONTROLLER2_IP} -name ca.key -type f -delete
    echo "[ETCD HA TASK - Done ] certs generated"

elif [ ${MY_HOSTNAME} == ${MST1} ];then
    echo "[ETCD HA TASK 3] Create certificates for ${CONTROLLER1_IP}"
	kubeadm init phase certs etcd-server --config=/ktmp/${CONTROLLER1_IP}/kubeadmcfg.yaml 2>/dev/null
	kubeadm init phase certs etcd-peer --config=/ktmp/${CONTROLLER1_IP}/kubeadmcfg.yaml 2>/dev/null
	kubeadm init phase certs etcd-healthcheck-client --config=/ktmp/${CONTROLLER1_IP}/kubeadmcfg.yaml 2>/dev/null
	kubeadm init phase certs apiserver-etcd-client --config=/ktmp/${CONTROLLER1_IP}/kubeadmcfg.yaml 2>/dev/null
	# No need to move the certs because they are generated locally
	ln -s /ktmp/${CONTROLLER1_IP}  /ktmp/local
    echo "[ETCD HA TASK - Done ] certs generated"
else
	echo '[ERROR]: HOST NOT SUPPORTED, check IP and HOSTNAME mapping in "source_in_all.sh"'
	exit 
fi
}

kubeadmcfg
gen_etcd_certs

echo "[ETCD HA TASK 4] On each host run the kubeadm command to generate a static manifest for etcd"


if [ ${MY_HOSTNAME} == ${MST1} ];then
	kubeadm init phase etcd local --config=/ktmp/local/kubeadmcfg.yaml 
	systemctl daemon-reload
	systemctl restart kubelet.service
else 
	kubeadm init phase etcd local --config=/ktmp/${MY_IP}/kubeadmcfg.yaml
	systemctl daemon-reload
	systemctl restart kubelet.service
fi
# echo "[TASK 9] Join ETCD cluster by Finding the IP and Name of 2 New Master VMs"
# KUBECONFIG=/etc/kubernetes/admin.conf kubectl exec -n kube-system etcd-${MST1} -- etcdctl --ca-file /etc/kubernetes/pki/etcd/ca.crt --cert-file /etc/kubernetes/pki/etcd/peer.crt --key-file /etc/kubernetes/pki/etcd/peer.key --endpoints=https://${CONTROLLER1_IP}:2379 member add ${CP1_HOSTNAME} https://${CP1_IP}:2380
