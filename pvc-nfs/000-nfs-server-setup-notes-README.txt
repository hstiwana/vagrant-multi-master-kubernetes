login to kmaster1 (10.10.10.21)
#####################
yum install nfs-utils libnfsidmap –y
systemctl enable rpcbind --now
systemctl enable nfs-server --now
systemctl start rpc-statd
systemctl start nfs-idmapd
mkdir -p /exports/data-0001
chmod 777 /exports/data-0001
echo '/exports/data-0001	*(rw,sync,no_root_squash)' >/etc/exports
exportfs -rv
####################RAW NFS Client use case in deployment################
kubectl create -f 1-use-raw-nfs-client-within-deployment-busybox.yaml
kubectl create -f 2-nginx-deployment-using-RAW-nfs-client.yaml
####################NFS Client filesytem but with PVCs###################
kubectl create -f 01-rbac.yaml
kubectl create -f 02-storage_class.yaml
kubectl create -f 03-create_deployment_for_nfs-client-provisioner.yaml
kubectl create -f 04-create-nfs-pvc_without_annotations_using_nfs-client-provisioner.yaml
## start creating pods or use in deployments #####
kubectl create -f 05-create_pod_and_use_pvc.yaml
kubectl create -f 06-create_a_test-pod_using_test-pvc_in_one.yaml
