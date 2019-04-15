# vagrant-multi-master-kubernetes
Vagrant CentOS based Multi-Master Kubernetes lab

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
