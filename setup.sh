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

# Check if NAMESPACE is set
if [ -z "$NAMESPACE" ]; then
    print_error "NAMESPACE environment variable is not set"
    print_error "Please set NAMESPACE to specify the target namespace"
    exit 1
fi

print_status "Using namespace: $NAMESPACE"

# Function to wait for pod to be ready
wait_for_pod() {
    local namespace=$1
    local pod_name=$2
    local timeout=300  # 5 minutes timeout
    
    print_status "Waiting for pod $pod_name to be ready..."
    
    for i in $(seq 1 $timeout); do
        status=$(kubectl get pod $pod_name -n $namespace -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$status" == "Running" ]; then
            print_status "Pod $pod_name is ready!"
            return 0
        fi
        sleep 1
    done
    
    print_error "Timeout waiting for pod $pod_name"
    return 1
}

# Function to check if namespace exists
check_namespace() {
    local namespace=$1
    if ! kubectl get namespace $namespace &>/dev/null; then
        print_status "Creating namespace $namespace..."
        kubectl create namespace $namespace
    else
        print_status "Namespace $namespace already exists"
    fi
}

# Main deployment process
print_status "Starting deployment process..."

# Create namespace
check_namespace "$NAMESPACE"

# Deploy webhook components
print_status "Deploying webhook components..."
NAMESPACE="$NAMESPACE" ./deploy.sh

# Wait for webhook pod to be ready
print_status "Waiting for webhook pod to be ready..."
webhook_pod=$(kubectl get pods -n "$NAMESPACE" -l app=pod-node-webhook -o jsonpath='{.items[0].metadata.name}')
wait_for_pod "$NAMESPACE" "$webhook_pod"

# Create first GPU pod
print_status "Creating first GPU pod..."
kubectl apply -f gpu-pod-1.yaml -n "$NAMESPACE"
wait_for_pod "$NAMESPACE" "gpu-pod-1"

# Create second GPU pod (should fail)
print_status "Creating second GPU pod (should fail)..."
kubectl apply -f gpu-pod-2.yaml -n "$NAMESPACE"

# Wait a bit and check status
sleep 5
print_status "Checking status of GPU pods..."
kubectl get pods -n "$NAMESPACE"

print_status "Setup completed!"
print_status "You can check the status of the pods with: kubectl get pods -n $NAMESPACE"
print_status "To see detailed information about the second pod's failure: kubectl describe pod gpu-pod-2 -n $NAMESPACE" 