#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if KUBECONFIG is set
if [ -z "$KUBECONFIG" ]; then
    print_error "KUBECONFIG environment variable is not set"
    print_error "Please set KUBECONFIG to point to your cluster's kubeconfig file"
    exit 1
fi

# Define namespaces and target nodes
WEBHOOK_NAMESPACE="webhook-system"
TEST_NAMESPACE_1="restricted-zone-1"
TEST_NAMESPACE_2="restricted-zone-2"
TEST_NAMESPACE_3="unrestricted-zone"
TARGET_NODE_1="psap-dev-dagray-1xl4-z2-fdkxq"
TARGET_NODE_2="psap-dev-dagray-1xl4-z2-gwwb2"
TARGET_NODE_3="psap-dev-dagray-1xl4-z2-x9bmx"

print_status "Using webhook namespace: $WEBHOOK_NAMESPACE"
print_status "Using test namespaces:"
print_status "- $TEST_NAMESPACE_1 (restricted to node $TARGET_NODE_1)"
print_status "- $TEST_NAMESPACE_2 (restricted to node $TARGET_NODE_2)"
print_status "- $TEST_NAMESPACE_3 (unrestricted)"

# Cleanup existing resources
print_status "Cleaning up existing resources..."
kubectl delete mutatingwebhookconfiguration pod-node-webhook --ignore-not-found=true
kubectl delete clusterrole pod-node-webhook --ignore-not-found=true
kubectl delete clusterrolebinding pod-node-webhook --ignore-not-found=true
kubectl delete namespace $WEBHOOK_NAMESPACE --ignore-not-found=true
kubectl delete namespace $TEST_NAMESPACE_1 --ignore-not-found=true
kubectl delete namespace $TEST_NAMESPACE_2 --ignore-not-found=true
kubectl delete namespace $TEST_NAMESPACE_3 --ignore-not-found=true

# Create namespaces
print_status "Creating namespaces..."
kubectl create namespace $WEBHOOK_NAMESPACE
kubectl create namespace $TEST_NAMESPACE_1
kubectl create namespace $TEST_NAMESPACE_2
kubectl create namespace $TEST_NAMESPACE_3

# Label namespaces with target nodes
print_status "Labeling namespaces with target nodes..."
kubectl label namespace $TEST_NAMESPACE_1 node.restriction/target=$TARGET_NODE_1
kubectl label namespace $TEST_NAMESPACE_2 node.restriction/target=$TARGET_NODE_2

# Deploy webhook components
print_status "Deploying webhook components..."
# Update namespace in YAML files
sed -i "s/namespace: node-restriction/namespace: $WEBHOOK_NAMESPACE/g" service-account.yaml deployment.yaml service.yaml
sed -i "s/namespace: node-restriction/namespace: $WEBHOOK_NAMESPACE/g" webhook-configuration.yaml

# Apply webhook components first
kubectl apply -f service-account.yaml
kubectl apply -f cluster-role.yaml
kubectl apply -f cluster-role-binding.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f webhook-configuration.yaml

# Generate certificates
print_status "Generating certificates..."
./generate-certs.sh

# Wait for webhook pod to be ready
print_status "Waiting for webhook pod to be ready..."
kubectl wait --for=condition=ready pod -l app=pod-node-webhook -n $WEBHOOK_NAMESPACE --timeout=60s

# Create test pods in all namespaces
print_status "Creating test pods (generic workloads) in all namespaces..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod-1
  namespace: $TEST_NAMESPACE_1
spec:
  containers:
  - name: nginx
    image: nginx:latest
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod-2
  namespace: $TEST_NAMESPACE_2
spec:
  containers:
  - name: nginx
    image: nginx:latest
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod-3
  namespace: $TEST_NAMESPACE_3
spec:
  containers:
  - name: nginx
    image: nginx:latest
EOF

print_status "Creating GPU pods in all namespaces..."
for ns in $TEST_NAMESPACE_1 $TEST_NAMESPACE_2 $TEST_NAMESPACE_3; do
    kubectl apply -f test-gpu-pod-1.yaml -n $ns
    kubectl apply -f test-gpu-pod-2.yaml -n $ns
done

# Wait for pods to be ready
print_status "Waiting for pods to be ready..."
for ns in $TEST_NAMESPACE_1 $TEST_NAMESPACE_2 $TEST_NAMESPACE_3; do
    kubectl wait --for=condition=ready pod nginx-pod-* -n $ns --timeout=60s || true
    kubectl wait --for=condition=ready pod gpu-pod-* -n $ns --timeout=60s || true
done

# Check pod status and node assignments
print_status "Checking pod status and node assignments..."
for ns in $TEST_NAMESPACE_1 $TEST_NAMESPACE_2 $TEST_NAMESPACE_3; do
    echo "=== Namespace: $ns ==="
    echo "Pod Status:"
    kubectl get pods -n $ns -o wide
    echo "Node Selectors:"
    kubectl get pods -n $ns -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeSelector}{"\n"}{end}'
    echo
done

print_status "Test completed!"
print_status "Summary of what to expect:"
print_status "1. In $TEST_NAMESPACE_1:"
print_status "   - All pods should be scheduled on node $TARGET_NODE_1"
print_status "2. In $TEST_NAMESPACE_2:"
print_status "   - All pods should be scheduled on node $TARGET_NODE_2"
print_status "3. In $TEST_NAMESPACE_3 (unrestricted):"
print_status "   - Pods should be scheduled based on normal Kubernetes scheduling rules"
print_status "\nYou can check the status of the pods with:"
for ns in $TEST_NAMESPACE_1 $TEST_NAMESPACE_2 $TEST_NAMESPACE_3; do
    print_status "kubectl get pods -n $ns -o wide"
done 