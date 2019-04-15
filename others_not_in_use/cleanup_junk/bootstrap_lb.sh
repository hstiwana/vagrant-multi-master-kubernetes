#!/bin/bash
source /vagrant/source_in_all.sh

# Enable ssh password authentication
echo "[TASK 1] Enable ssh password authentication"
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl reload sshd

# Set Root password
echo "[TASK 2] Set root password"
echo "${rootpwd}" | passwd --stdin root >/dev/null 2>&1

# Update hosts file
echo "[TASK 3] Update /etc/hosts file and set ${public_gw} as default gw"
cat >>/etc/hosts<<EOF
$etchosts
EOF

pub_net

# Install Nginx
echo "[TASK 4] Install Nginx to configure as LB"
yum install -d0 -y -q sshpass

# Disable SELinux
echo "[TASK 5] Set SELinux in permissive mode (effectively disabling it)"
setenforce 0
sed -i --follow-symlinks 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Stop and disable firewalld
echo "[TASK 6] Stop and Disable firewalld"
systemctl disable --now firewalld >/dev/null 2>&1

# Disable swap
echo "[TASK 7] Disable and turn off SWAP"
sed -i '/swap/d' /etc/fstab
swapoff -a

# Add yum repo file for Kubernetes
echo "[TASK 8] Add yum repo file for kubernetes"
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
echo "[TASK 9] Install Kubernetes (kubeadm, kubelet and kubectl)"
yes|yum install -d0 -y -q kubectl-${k8s_ver}

# Update bashrc file
echo "[TASK 10] Update /etc/bashrc file"
echo "export TERM=xterm" >> /etc/bashrc
# echo "source <(kubectl completion bash)" >> /etc/bashrc
if [ $(grep kubectl /etc/bashrc|wc -l) != 1 ]; then sudo su - -c "echo 'source <(kubectl completion bash)' >> /etc/bashrc"; else echo "Entry Found"; fi


echo "[TASK 11] Setting up a Kube API Frontend Load Balancer with NGINX"
cat >/etc/yum.repos.d/nginx.repo<<EOF
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=0
enabled=1
EOF

yes|yum -d0 -q -y install nginx
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

    upstream etcdha {
        server $CONTROLLER1_IP:2380;
        server $CONTROLLER2_IP:2380;
        server $CONTROLLER3_IP:2380;
    }

    server {
        listen 2380;
 #       listen 2379;
        proxy_pass etcdha;
    }
}
EOF

systemctl enable --now nginx

#curl -k https://localhost:6443/version
