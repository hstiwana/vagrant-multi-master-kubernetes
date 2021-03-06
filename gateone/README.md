## Deploy "GateOne" in your kubernetes cluster from docker image
1) untar file from "gateone" directory
     ```
     untar xzf gateone.tar.gz
     cd gateone
     ```
2) build your container from Dockerfile
      ```
      docker build -t gateone .
      ```
3) Run your newly built GateOne container so that we can export it
      ```
      docker run --rm --name gateone -p 443:10443 -d gateone 
     ``` 
4) export the image (i tried save but it did not work as expected, export works well)
      ```
      docker export gateone -o /tmp/gateone.tar
      ```
5) Copy exported gateone.tar file on your 3 nodes and import it using docker 
      ```
      scp /tmp/gateone.tar root@nodeX:/tmp/
      ```
6) Login to your nodes and import the image, also tag your image
      ```
      ssh root@nodeX
      docker import /tmp/gateone.tar > /tmp/imageid 2>&1
      gateoneimageid=$(cut -d: -f2 /tmp/imageid)
      docker tag $gateoneimageid gateone
      ```
7) Check if image is correctly tagged and try running docker manually.
      ```
      docker images |grep -i gateone
      docker run --rm  -p 443:10443 -it gateone:latest /GateOne/run_gateone.py
      ```
8) If all looks good on all 3 nodes, stop your "gateone" process runining on your nodes and prepare your deployment.
   **--image-pull-policy Never**  is the key here that makes a local image work with k8s.
      ```
      kubectl run gateone --image gateone --image-pull-policy Never --dry-run -o yaml --port 10443 --expose --hostport 443 --command -- /GateOne/run_gateone.py |sed 's/port: 10443/port: 443/1' >/tmp/gateone.yaml
      kubectl create -f /tmp/gateone.yaml
      ```
9) Scale your deployment to run one pod on each node.
     ```
     kubectl scale deployment gateone --replicas 3
     ```
10) If you want to make your service available from your external network, edit your service and add **externalIPs** section to it.
      ```
      kubectl edit service gateone
     ``` 
It should look something like this. Make sure to use your **NodeX** IP details e.g. I am using 192.168.0.4X here.

```
apiVersion: v1
kind: Service
metadata:
  creationTimestamp: null
  name: gateone
  selfLink: /api/v1/namespaces/default/services/gateone
spec:
  externalIPs:
  - 192.168.0.41
  - 192.168.0.42
  - 192.168.0.43
  ports:
  - port: 443
    protocol: TCP
    targetPort: 10443
  selector:
    run: gateone
  sessionAffinity: None
  type: ClusterIP
status:
  loadBalancer: {}
```
Once your service edit is done, you can see **EXTERNAL-IP** listed in your service status.
```
kmaster1# kubectl get service gateone
NAME      TYPE        CLUSTER-IP       EXTERNAL-IP                              PORT(S)   AGE
gateone   ClusterIP   10.100.144.252   192.168.0.41,192.168.0.42,192.168.0.43   443/TCP   37m
```
