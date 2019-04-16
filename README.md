# vagrant-multi-master-kubernetes
Vagrant CentOS based Multi-Master Kubernetes lab

NOTE: Vagrant and VirtualBox are required to use this lab.

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



Future Plans:-
1) Upgrade your cluster to v1.14.1
	a) On your first master node run the following
		
		[root@kmaster1 ~]# kubeadm upgrade plan 1.14.1

	Once all your checks are looking good, you can apply this upgrade plan to your cluster
		
		[root@kmaster1 ~]# yum -y update kubeadmin-1.14.1-0.x86_64 
		[root@kmaster1 ~]#  kubeadm upgrade apply 1.14.1 

	b) Wait for it to complete and replace versions for static pods (kube-apiserver, kube-controller-manager, kube-scheduler)
		
		[root@kmaster1 ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-apiserver.yaml  
		[root@kmaster1 ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-controller-manager.yaml 
		[root@kmaster1 ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-scheduler.yaml  

		[root@kmaster1 ~]# grep -i  k8s.gcr.io /etc/kubernetes/manifests/*.yaml
		/etc/kubernetes/manifests/etcd.yaml:    image: k8s.gcr.io/etcd:3.3.10
		/etc/kubernetes/manifests/kube-apiserver.yaml:    image: k8s.gcr.io/kube-apiserver:v1.14.1
		/etc/kubernetes/manifests/kube-controller-manager.yaml:    image: k8s.gcr.io/kube-controller-manager:v1.14.1
		/etc/kubernetes/manifests/kube-scheduler.yaml:    image: k8s.gcr.io/kube-scheduler:v1.14.1
		[root@kmaster1 ~]#



	c) Wait for few minutes and let static pods to restart with new changes, now install new version of "kubelet"

		[root@kmaster1 ~]# yum -u update kubelet-1.14-1.0.x86_64
		[root@kmaster1 ~]# kubeadm upgrade node config --kubelet-version $(kubelet --version | cut -d ' ' -f 2)
		[root@kmaster1 ~]# systemctl daemon-reload && system restart kubelet
	
	d) Now we need to do the same for static pods (kube-apiserver, kube-controller-manager, kube-scheduler, kubelet) on other managers
	e) etcd static pod needs to match version with 1st master in cluster

		[root@kmaster2 ~]# yum update kubeadmin-1.14.1-0.x86_64 kubelet-1.14-1.0.x86_64
		[root@kmaster2 ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-apiserver.yaml  
		[root@kmaster2 ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-controller-manager.yaml 
		[root@kmaster2 ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-scheduler.yaml  
		[root@kmaster2 ~]# sed -i 's/3.2.24/3.3.10/g' /etc/kubernetes/manifests/etcd.yaml
		
		[root@kmaster3 ~]# yum update kubeadmin-1.14.1-0.x86_64 kubelet-1.14-1.0.x86_64
		[root@kmaster3 ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-apiserver.yaml 
		[root@kmaster3 ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-controller-manager.yaml 
		[root@kmaster3 ~]# sed -i 's/v1.13.2/1.14.1/g' /etc/kubernetes/manifests/kube-scheduler.yaml  
		[root@kmaster3 ~]# sed -i 's/3.2.24/3.3.10/g' /etc/kubernetes/manifests/etcd.yaml
		
	f) On each node, do the following (please cordon, drain nodes before doing it, don't forget to uncordon them)
		
		[root@nodeX ~]# yum -u update kubelet-1.14-1.0.x86_64
		[root@nodeX ~]# kubeadm upgrade node config --kubelet-version $(kubelet --version | cut -d ' ' -f 2) 
		[root@nodeX ~]# systemctl daemon-reload && system restart kubelet
	
