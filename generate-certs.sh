#!/bin/bash

set -e

# Define webhook namespace
WEBHOOK_NAMESPACE="webhook-system"

# Create a temporary directory for certificates
CERT_DIR=$(mktemp -d)
echo "[INFO] Created temporary directory for certificates: $CERT_DIR"

# Generate CA private key and certificate
openssl genrsa -out $CERT_DIR/ca.key 2048
openssl req -new -x509 -days 365 -key $CERT_DIR/ca.key -subj "/CN=pod-node-webhook-ca" -out $CERT_DIR/ca.crt

# Generate server private key and CSR
openssl genrsa -out $CERT_DIR/server.key 2048
openssl req -new -key $CERT_DIR/server.key -subj "/CN=pod-node-webhook.$WEBHOOK_NAMESPACE.svc" -out $CERT_DIR/server.csr

# Sign the server certificate with the CA
openssl x509 -req -in $CERT_DIR/server.csr -CA $CERT_DIR/ca.crt -CAkey $CERT_DIR/ca.key \
    -CAcreateserial -out $CERT_DIR/server.crt -days 365 \
    -extensions v3_req -extfile <(cat <<-EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = pod-node-webhook
DNS.2 = pod-node-webhook.$WEBHOOK_NAMESPACE
DNS.3 = pod-node-webhook.$WEBHOOK_NAMESPACE.svc
EOF
)

# Create Kubernetes secret with the certificates
kubectl create secret generic webhook-certs \
    --from-file=tls.key=$CERT_DIR/server.key \
    --from-file=tls.crt=$CERT_DIR/server.crt \
    --from-file=ca.crt=$CERT_DIR/ca.crt \
    -n $WEBHOOK_NAMESPACE

# Update the webhook configuration with the CA bundle
CA_BUNDLE=$(cat $CERT_DIR/ca.crt | base64 | tr -d '\n')
kubectl patch mutatingwebhookconfiguration pod-node-webhook --type='json' -p="[{\"op\": \"add\", \"path\": \"/webhooks/0/clientConfig/caBundle\", \"value\":\"$CA_BUNDLE\"}]"

# Clean up
rm -rf $CERT_DIR
echo "[INFO] Certificates generated and secret created successfully!" 