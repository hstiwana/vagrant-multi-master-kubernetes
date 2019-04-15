#!/bin/bash
source /vagrant/source_in_all.sh

# Enable ssh password authentication
echo "[TASK 1] Enable ssh password authentication"
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl reload sshd
systemctl disable --now NetworkManager

# Set Root password
echo "[TASK 2] Set root password"
echo ${rootpwd} | passwd --stdin root >/dev/null 2>&1

# Remove eth0 and setup gateway
echo "[TASK 3] Update gateway to ${public_gw} for installations to work"
#call pub_net function from sourced script
pub_net
yum -d0 -q -y install net-tools vim lsof

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

## Create /etc/docker directory.
mkdir /etc/docker 2>/dev/null

# Setup daemon.
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

mkdir -p /etc/systemd/system/docker.service.d

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
yum install -d0 -y -q kubeadm-${k8s_ver} kubelet-${k8s_ver} kubectl-${k8s_ver} kubernetes-cni-${cni_ver} 

# Update vagrant user's bashrc file
echo "[TASK 13] Update /etc/bashrc file"
echo "export TERM=xterm" >> /etc/bashrc
# echo "source <(kubectl completion bash)" >> /etc/bashrc
if [ $(grep kubectl /etc/bashrc|wc -l) != 1 ]; then sudo su - -c "echo 'source <(kubectl completion bash)' >> /etc/bashrc"; else echo "Entry Found"; fi

# Remove eth0 and setup gateway
# echo "[TASK 14] Update gateway to ${private_gw}"
# pri_net

echo "[TASK 14] Add entry in /etc/rc.local to ensure correct correct routes"
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
sleep 5
if [ $(grep tcpconf.d /etc/nginx/nginx.conf|wc -l) != 1 ]; then
        sudo su - -c "echo 'include /etc/nginx/tcpconf.d/*;' >> /etc/nginx/nginx.conf";
else
        echo "Entry Found";
fi
cat << EOF | sudo tee /etc/nginx/tcpconf.d/kubernetes.conf
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

systemctl enable --now nginx


for MST in ${MST1} ${MST2} ${MST3}
do
	if [ ${MST} == ${MST1} ]; then
		echo "[BOOTSTRAP TASK 18] Setting up a ETCD HA Cluster on ${MST}"
		sshpass -p ${rootpwd} ssh ${opts} -qt root@${MST} '/vagrant/bootstrap_etcd_ha.sh'
		echo
		echo
		echo "######## [DONE] ----> [BOOTSTRAP TASK 18] Setting up a ETCD HA Cluster on ${MST} ###########"
		echo 
	else
		### ETCD and Kubernetes on MST2 and MST3
		echo "[BOOTSTRAP TASK 19] Setting up a ETCD HA Cluster on ${MST}"
		sshpass -p ${rootpwd} ssh ${opts} -qt root@${MST} '/vagrant/bootstrap_etcd_ha.sh'
		echo
		echo
		echo "######## [DONE] ----> [BOOTSTRAP TASK 19] Setting up a ETCD HA Cluster on ${MST} ###########"
		echo 
	fi
done

for MST in ${MST1} ${MST2} ${MST3}
do
	if [ ${MST} == ${MST1} ]; then
		echo "[BOOTSTRAP TASK 18.1] Setting up K8s HA Cluster on ${MST}"
		sshpass -p ${rootpwd} ssh ${opts} -qt root@${MST} '/vagrant/bootstrap_kmaster.sh'
		echo
		echo
		echo "######### [DONE] ----> [BOOTSTRAP TASK 18.1] Setting up K8s HA Cluster on ${MST} ###########"
		echo
	else
		echo "[BOOTSTRAP TASK 19.1] Setting up K8s HA Cluster on ${MST}"
		sshpass -p ${rootpwd} ssh ${opts} -qt root@${MST} '/vagrant/bootstrap_kmaster_others.sh'
		echo
		echo
		echo "######### [DONE] ----> [BOOTSTRAP TASK 19.1] Setting up K8s HA Cluster on ${MST} ###########"
		echo 
	fi
done

for WORKER in ${WKR1} ${WKR2} ${WKR3}
do
	echo "[BOOTSTRAP TASK 19.1] Joining ${WORKER} in K8s HA Cluster"
	sshpass -p ${rootpwd} ssh ${opts} -qt root@${WORKER} '/vagrant/bootstrap_kworker.sh'
	echo
	echo
	echo "######### [DONE] ----> [BOOTSTRAP TASK 19.1] Joined K8s HA Cluster as ${WORKER} ###########"

done
fi
