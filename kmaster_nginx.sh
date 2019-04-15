#!/bin/bash
source /vagrant/source_in_all.sh
cat >/etc/yum.repos.d/nginx.repo<<EOF
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=0
enabled=1
EOF

yes|yum -d0 -q -y install nginx

cat > /etc/nginx/conf.d/kubernetes.default.svc.cluster.local.conf << EOF
server {
  listen      80;
  server_name kubernetes.default.svc.cluster.local;

  location /healthz {
     proxy_pass                    https://${MY_IP}:6443/healthz;
     proxy_ssl_trusted_certificate /etc/kubernetes/pki/ca.crt;
  }
}
EOF

systemctl enable --now nginx
systemctl restart nginx
sleep 5
