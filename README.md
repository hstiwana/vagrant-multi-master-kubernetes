# vagrant-multi-master-kubernetes [HA]
Vagrant CentOS based Multi-Master [HA] Kubernetes lab

# NOTE 1: Vagrant and VirtualBox are required to use this lab.
# NOTE 2: Please update "Vagrantfile" and "source_in_all.sh" script with your network settings.
# NOTE 2.1: Replace YOUR_PUBLIC_HOSTNAME and YOUR_PUBLIC_IP to enable kubectl to work remotely too.



=====================================================================
# ==== START underlying Hardware / VM config ====
# Tools for unerlying hardware configuration (versions e.t.c.)

Following was done on a RHEL 7.4 running physical server and it is known to work.
we are creating a separate volume of 100G to store our VM images.


	lvcreate -L +100G -n kubernetes vg00
	mkfs.ext4 /dev/mapper/vg00-kubernetes
	mkdir /kubernetes 2>/dev/null
	if [ $(grep /kubernetes /etc/fstab|wc -l) != 1 ]; then echo "/dev/mapper/vg00-kubernetes /kubernetes                ext4    defaults        1 2" >> /etc/fstab; else echo "fstab Entry Found"; fi
	mount /kubernetes && cd /kubernetes
	yes|yum -d0 -q -y install https://releases.hashicorp.com/vagrant/2.2.4/vagrant_2.2.4_x86_64.rpm
	vagrant plugin install vagrant-vbguest
	yum -d0 -q -y install kernel-devel kernel-headers make patch gcc git xauth
	wget -q https://download.virtualbox.org/virtualbox/rpm/el/virtualbox.repo -P /etc/yum.repos.d
	yes|yum -d0 -q -y  install VirtualBox-6.0.x86_64
	systemctl enable --now vboxdrv; systemctl status vboxdrv
	wget -q https://download.virtualbox.org/virtualbox/6.0.4/Oracle_VM_VirtualBox_Extension_Pack-6.0.4.vbox-extpack
	yes|VBoxManage extpack install  Oracle_VM_VirtualBox_Extension_Pack-6.0.4.vbox-extpack
	rm -rf Oracle_VM_VirtualBox_Extension_Pack-6.0.4.vbox-extpack
	rm -rf ~/VirtualBox\ VMs
	mkdir "/kubernetes/VirtualBoxVMs/" 2>/dev/null
	ln -s /kubernetes/VirtualBoxVMs/ ~/VirtualBox\ VMs
	sed -i '/swap/d' /etc/fstab; swapoff -a
# ==== END underlying Hardware / VM config ====
=====================================================================





1) Clone this repo and cd into the directory

    	git clone  https://github.com/hstiwana/vagrant-multi-master-kubernetes.git && cd vagrant-multi-master-kubernetes

2) Build base image first (it will help to speed up VM boot because it will install "Virtualbox Guest Additions")

     	cd buildbase && vagrant up

3) Package this VM with name "kub-base-centos76", this will be used to build our Kubernetes VMs
	
     	vagrant package --output kub-base-centos76

4) Add newly generated image "kub-base-centos76" in your vagrant "box"
		
     	vagrant box add kub-base-centos76 --name kub-base-centos76

5) Now we are ready to build our lab with 3 masters and 3 nodes
		
    	cd ../ && vagrant validate && vagrant up



# Future Plans / Cluster Upgrades :-
 Upgrade your cluster to v1.14.1
	
 1) On your first master node run the following
		
    	[root@kmaster1 ~]# kubeadm upgrade plan 1.14.1

    Once all your checks are looking good, you can apply this upgrade plan to your cluster
		
    	[root@kmaster1 ~]# yum -y update kubeadmin-1.14.1-0.x86_64 
    	[root@kmaster1 ~]#  kubeadm upgrade apply 1.14.1 

 2) Wait for it to complete and replace versions for static pods (kube-apiserver, kube-controller-manager, kube-scheduler)
		
    	[root@kmaster1 ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-apiserver.yaml  
    	[root@kmaster1 ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-controller-manager.yaml 
    	[root@kmaster1 ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-scheduler.yaml  

    	[root@kmaster1 ~]# grep -i  k8s.gcr.io /etc/kubernetes/manifests/*.yaml
    	/etc/kubernetes/manifests/etcd.yaml:    image: k8s.gcr.io/etcd:3.3.10
    	/etc/kubernetes/manifests/kube-apiserver.yaml:    image: k8s.gcr.io/kube-apiserver:v1.14.1
    	/etc/kubernetes/manifests/kube-controller-manager.yaml:    image: k8s.gcr.io/kube-controller-manager:v1.14.1
    	/etc/kubernetes/manifests/kube-scheduler.yaml:    image: k8s.gcr.io/kube-scheduler:v1.14.1
    	[root@kmaster1 ~]#

 3) Wait for few minutes and let static pods to restart with new changes, now install new version of "kubelet"

    	[root@kmaster1 ~]# yum -u update kubelet-1.14-1.0.x86_64
    	[root@kmaster1 ~]# kubeadm upgrade node config --kubelet-version $(kubelet --version | cut -d ' ' -f 2)
    	[root@kmaster1 ~]# systemctl daemon-reload && system restart kubelet
	
 4) Now we need to do the same for static pods (kube-apiserver, kube-controller-manager, kube-scheduler, kubelet) on other managers
	
 5) etcd static pod needs to match version with 1st master in cluster

    	[root@kmasterX ~]# yum update kubeadmin-1.14.1-0.x86_64 kubelet-1.14-1.0.x86_64
    	[root@kmasterX ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-apiserver.yaml  
    	[root@kmasterX ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-controller-manager.yaml 
    	[root@kmasterX ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-scheduler.yaml  
    	[root@kmasterX ~]# sed -i 's/3.2.24/3.3.10/g' /etc/kubernetes/manifests/etcd.yaml
			
 6) On each node, do the following (please "cordon", "drain" nodes before doing it, don't forget to "uncordon" them)
		
    	[root@nodeX ~]# yum -u update kubelet-1.14-1.0.x86_64
    	[root@nodeX ~]# kubeadm upgrade node config --kubelet-version $(kubelet --version | cut -d ' ' -f 2) 
    	[root@nodeX ~]# systemctl daemon-reload && system restart kubelet
   
 7) Check your node versions with kubectl get nodes.
   
     	[root@kmasterX ~]# kubectl get nodes
    	NAME                STATUS   ROLES    AGE   VERSION
    	kmaster1.lk8s.net   Ready    master   24h   v1.14.1
    	kmaster2.lk8s.net   Ready    master   24h   v1.14.1
    	kmaster3.lk8s.net   Ready    master   24h   v1.14.1
    	node1.lk8s.net      Ready    <none>   24h   v1.14.1
    	node2.lk8s.net      Ready    <none>   24h   v1.14.1
    	node3.lk8s.net      Ready    <none>   24h   v1.14.1
	


# Bugs / issues:-
