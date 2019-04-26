#!/bin/bash
chmod +x /vagrant/*.sh
export k8s_rpm_ver="1.13.2-0" # yum list --showduplicates kubeadm --disableexcludes=kubernetes #1.13.2-0
export K8S_VERSION='1.13.2' #will use during intial cluster setup with /etc/kubernetes/pki/kubeadm-config-`hostname -f`.yaml
export cni_ver="0.6.0"
export K8S_CLUSTER_NAME=lk8s.net
export OUTPUT_DIR=$(realpath -m /kube/_clusters/${K8S_CLUSTER_NAME})
export LOCAL_CERTS_DIR=${OUTPUT_DIR}/pki
export KUBECONFIG=${OUTPUT_DIR}/kubeconfig
export MASTER_SSH_ADDR_1=root@10.10.10.21
export BASE_DNS1=8.8.8.8
export BASE_DNS2=1.1.1.1

export tokenTTL=0 #never expire
export docker_ver="ce-18.06.3.ce"
export public_gw=192.168.0.1
export private_gw=10.10.10.1
export nat_gw=10.0.2.2
export LOCAL_CERTS_DIR=/etc/kubernetes/pki

export nat_eth=eth0
export private_eth=eth1
export public_eth=eth2

# SSH password and Options
export rootpwd=kubeadmin
export opts=" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
#export net_plugin=weave-net
export net_plugin=flannel

# Following IP/Vars are for "MASTER" nodes, we will run ETCD on them.
export PUB_HOST=YOUR_PUBLIC_HOSTNAME
export PUB_IP=YOUR_PUBLIC_IP
export K8S_API_ADDVERTISE_IP_1=10.10.10.21
export CONTROLLER1_IP=${K8S_API_ADDVERTISE_IP_1}
export CONTROLLER2_IP=10.10.10.22
export CONTROLLER3_IP=10.10.10.23
export WHOST1=10.10.10.41
export WHOST2=10.10.10.42
export WHOST3=10.10.10.43
export ETCD_VIP=10.10.10.110
export LLBIP=10.10.10.10
export PLBIP=192.168.0.10
export K8S_API_ENDPOINT_INTERNAL=kmaster1.lk8s.net
export MST1=${K8S_API_ENDPOINT_INTERNAL}
export MST2=kmaster2.lk8s.net
export MST3=kmaster3.lk8s.net
export WKR1=node1.lk8s.net
export WKR2=node2.lk8s.net
export WKR3=node3.lk8s.net
export K8S_API_ENDPOINT=lb.lk8s.net
export LPLB=${K8S_API_ENDPOINT}
export PPLB=lb.pk8s.com
export controlPlaneEndpointPort=6443
export controlPlaneEndpoint=${K8S_API_ENDPOINT}:${controlPlaneEndpointPort}
export dnsDomain=cluster.local
export serviceSubnet="10.96.0.0/12"
export podSubnet="10.244.0.0/16"
export ETCDHOSTS=(${CONTROLLER1_IP} ${CONTROLLER2_IP} ${CONTROLLER3_IP})
export NAMES=(${MST1} ${MST2} ${MST3})
export MY_IP=$(ip a show dev ${private_eth}|grep -w inet|awk -F/ '{print $1}'|awk '{print $2}')
export MY_HOSTNAME=$(hostname -f)

export CP0_HOSTNAME=${MST1}
export kubeconfig=/etc/kubernetes/admin.conf

export kubeadminitopts=" --ignore-preflight-errors=Port-6443 --ignore-preflight-errors=Port-10251 --ignore-preflight-errors=Port-10252 --ignore-preflight-errors=DirAvailable--etc-kubernetes-manifests --ignore-preflight-errors=DirAvailable--etc-kubernetes-manifests --ignore-preflight-errors=Port-10250 --ignore-preflight-errors=FileAvailable--etc-kubernetes-manifests-kube-scheduler.yaml --ignore-preflight-errors=FileAvailable--etc-kubernetes-manifests-kube-apiserver.yaml --ignore-preflight-errors=FileAvailable--etc-kubernetes-manifests-kube-controller-manager.yaml --ignore-preflight-errors=FileAvailable--etc-kubernetes-manifests-etcd.yaml"

export etchosts="
${PLBIP} ${PPLB} lbp
${LLBIP} ${K8S_API_ENDPOINT} lb
${CONTROLLER1_IP} ${MST1} kmaster1
${CONTROLLER2_IP} ${MST2} kmaster2
${CONTROLLER3_IP} ${MST3} kmaster3
${WHOST1} ${WKR1} node1
${WHOST2} ${WKR2} node2
${WHOST3} ${WKR3} node3
"


egrep -v '^#|^$|^nameserver' /etc/resolv.conf > /etc/resolv.conf_new

for BASE_DNS in ${BASE_DNS1} ${BASE_DNS2}
 do
	echo "nameserver ${BASE_DNS}" >>/etc/resolv.conf_new
done

mv -f /etc/resolv.conf_new /etc/resolv.conf


pub_net(){
	echo "[FIX_NET public_net] setting gateway to public address ${public_gw}"
	#delete virtualbox route for first interface used as NAT
	nat_route=$(ip route |grep ${nat_eth}|grep default)
        if [ "${nat_route}" != ""  ]; then
                delroute="ip route delete $(ip route |grep ${nat_eth}|grep default)"
                echo  $delroute|sudo bash  > /dev/null 2>&1
        else
                echo "N/A"  > /dev/null 2>&1
        fi
	route delete default gw ${private_gw} > /dev/null 2>&1

	route add default gw ${public_gw} > /dev/null 2>&1
	route -A inet6 add default gw fc00::1 ${public_eth} > /dev/null 2>&1
	echo '.... done'
}

nat_net(){
	echo "[FIX_NET public_NAT_net] setting gateway to NAT address ${nat_gw}"
        route delete default gw ${public_gw} > /dev/null 2>&1
	route delete default gw ${private_gw} > /dev/null 2>&1
        #add back virtualbox route for first interface used as NAT
	route add default gw ${nat_gw} > /dev/null 2>&1
	route -A inet6 add default gw fc00::1 ${nat_eth} > /dev/null 2>&1
	echo '.... done'
}

pri_net(){
	echo "[FIX_NET private_net] setting gateway to private address ${private_gw}"
	route delete default gw ${public_gw} > /dev/null 2>&1
	route -A inet6 delete default gw fc00::1 ${public_eth} > /dev/null 2>&1
	nat_route=$(ip route |grep ${nat_eth}|grep default)
        if [ "${nat_route}" != ""  ]; then
                delroute="ip route delete $(ip route |grep ${nat_eth}|grep default)"
                echo  $delroute|sudo bash  > /dev/null 2>&1
        else
                echo "N/A"  > /dev/null 2>&1
        fi

	route add default gw ${private_gw} > /dev/null 2>&1
	route -A inet6 add default gw fc00::1 ${private_eth} > /dev/null 2>&1
	echo '.... done'
}

etcd_status(){
echo "Checking cluster state to ensure ETCD cluster is up before starting K8s HA config"
until echo ${state} | grep -m 1 "cluster is healthy"; do
    state=$(docker run --rm -i --net host -v /etc/kubernetes:/etc/kubernetes k8s.gcr.io/etcd:3.2.24 etcdctl --cert-file /etc/kubernetes/pki/etcd/peer.crt --key-file /etc/kubernetes/pki/etcd/peer.key --ca-file /etc/kubernetes/pki/etcd/ca.crt --endpoints https://${MY_IP}:2379 cluster-health|tail -1);
    sleep 5;
    echo "ETCD : ${state}";
done
}
# version check using ETCDCTL_API 3
#docker run --rm -i --net host -v /etc/kubernetes:/etc/kubernetes k8s.gcr.io/etcd:3.2.24 /bin/sh -c "export ETCDCTL_API=3 && /usr/local/bin/etcdctl  --cert=/etc/kubernetes/pki/etcd/peer.crt --key=/etc/kubernetes/pki/etcd/peer.key --cacert=/etc/kubernetes/pki/etcd/ca.crt --endpoints https://10.10.10.21:2379,https://10.10.10.22:2379,https://10.10.10.23:2379 --write-out="table" endpoint status"
