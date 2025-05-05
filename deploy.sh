#!/bin/bash

# Create namespace if it doesn't exist
kubectl create namespace node-restriction --dry-run=client -o yaml | kubectl apply -f -

# Create OpenSSL config file
cat > openssl.cnf << EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = pod-node-webhook.node-restriction.svc
DNS.2 = pod-node-webhook.node-restriction.svc.cluster.local
EOF

# Generate CA certificate
openssl genrsa -out ca.key 2048
openssl req -new -x509 -days 365 -key ca.key -subj "/CN=pod-node-webhook.node-restriction.svc" -out ca.crt

# Generate server certificate
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=pod-node-webhook.node-restriction.svc" -out server.csr -config openssl.cnf
openssl x509 -req -in server.csr -days 365 -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -extensions v3_req -extfile openssl.cnf

# Create TLS secret
kubectl create secret tls webhook-certs \
    --cert=server.crt \
    --key=server.key \
    -n node-restriction \
    --dry-run=client -o yaml | kubectl apply -f -

# Get CA bundle
CA_BUNDLE=$(cat ca.crt | base64 | tr -d '\n')

# Deploy RBAC
kubectl apply -f rbac.yaml

# Deploy webhook
kubectl apply -f deployment.yaml

# Deploy webhook configuration
cat webhook-config.yaml | sed "s/\${CA_BUNDLE}/${CA_BUNDLE}/" | kubectl apply -f -

# Clean up
rm ca.key ca.crt ca.srl server.key server.csr server.crt openssl.cnf 