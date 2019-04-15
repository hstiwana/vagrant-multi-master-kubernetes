#!/usr/bin/env bash
source /vagrant/source_in_all.sh
export OPENSSL=/usr/bin/openssl
export CA_CERT_HASH=$(openssl x509 -pubkey -in ${LOCAL_CERTS_DIR}/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* /sha256:/')
export CERTS_DIR=${1:-$LOCAL_CERTS_DIR}
export CA="${CERTS_DIR}"/ca.crt
export CA_KEY="${CERTS_DIR}"/ca.key

if [[ ! -f ${CA} || ! -f ${CA_KEY} ]]; then
   echo "Error: CA files ${CA}  ${CA_KEY} are missing "
   exit 1
fi

export CLIENT_SUBJECT=${CLIENT_SUBJECT:-"/O=system:masters/CN=kubernetes-admin"}
export CLIENT_CSR=${CERTS_DIR}/kubeadmin.csr
export CLIENT_CERT=${CERTS_DIR}/kubeadmin.crt
export CLIENT_KEY=${CERTS_DIR}/kubeadmin.key
export CLIENT_CERT_EXTENSION=${CERTS_DIR}/cert-extension

# We need faketime for cases when your client time is on UTC+
#which faketime >/dev/null 2>&1
#if [[ $? == 0 ]]; then
#  OPENSSL="faketime -f -1d openssl"
#else
#  echo "Warning, faketime is missing, you might have a problem if your server time is less tehn"
#export   OPENSSL=openssl
#fi
#
echo "OPENSSL = $OPENSSL "
echo "Creating Client KEY $CLIENT_KEY "
$OPENSSL genrsa -out "$CLIENT_KEY" 2048

echo "Creating Client CSR $CLIENT_CSR "
$OPENSSL req -subj "${CLIENT_SUBJECT}" -sha256 -new -key "${CLIENT_KEY}" -out "${CLIENT_CSR}"

echo "--- create  ca extfile"
echo "extendedKeyUsage=clientAuth" > "$CLIENT_CERT_EXTENSION"

echo "--- sign  certificate ${CLIENT_CERT} "
$OPENSSL x509 -req -days 1096 -sha256 -in "$CLIENT_CSR" -CA "$CA" -CAkey "$CA_KEY" \
-CAcreateserial -out "$CLIENT_CERT" -extfile "$CLIENT_CERT_EXTENSION" -passin pass:"$CA_PASS"
export CLIENT_CERT_B64=$(base64 -w0  < $LOCAL_CERTS_DIR/kubeadmin.crt)
export CLIENT_KEY_B64=$(base64 -w0  < $LOCAL_CERTS_DIR/kubeadmin.key)
export CA_DATA_B64=$(base64 -w0  < $LOCAL_CERTS_DIR/ca.crt)

cat >${LOCAL_CERTS_DIR}/kubeconfig-${MST1}.yaml<<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${CA_DATA_B64}
    server: https://${controlPlaneEndpoint}:6443
  name: ${K8S_CLUSTER_NAME}
contexts:
- context:
    cluster: ${K8S_CLUSTER_NAME}
    user: ${K8S_CLUSTER_NAME}-admin
    namespace: default
  name: ${K8S_CLUSTER_NAME}
current-context: ${K8S_CLUSTER_NAME}
kind: Config
preferences: {}
users:
- name: ${K8S_CLUSTER_NAME}-admin
  user:
    client-certificate-data: ${CLIENT_CERT_B64}
    client-key-data: ${CLIENT_KEY_B64}
EOF
