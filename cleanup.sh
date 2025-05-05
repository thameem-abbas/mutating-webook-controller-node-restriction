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

# Define namespaces
WEBHOOK_NAMESPACE="webhook-system"
TEST_NAMESPACE_1="restricted-zone-1"
TEST_NAMESPACE_2="restricted-zone-2"
TEST_NAMESPACE_3="unrestricted-zone"

print_status "Starting cleanup process..."

# Delete pods in test namespaces
for ns in "$TEST_NAMESPACE_1" "$TEST_NAMESPACE_2" "$TEST_NAMESPACE_3"; do
    print_status "Deleting pods in namespace $ns..."
    kubectl delete pod --all -n "$ns" --ignore-not-found
done

# Delete the MutatingWebhookConfiguration
print_status "Deleting MutatingWebhookConfiguration..."
kubectl delete mutatingwebhookconfiguration pod-node-webhook --ignore-not-found

# Delete the ClusterRole and ClusterRoleBinding
print_status "Deleting ClusterRole and ClusterRoleBinding..."
kubectl delete clusterrole pod-node-webhook --ignore-not-found
kubectl delete clusterrolebinding pod-node-webhook --ignore-not-found

# Delete the Deployment and Service
print_status "Deleting Deployment and Service..."
kubectl delete deployment pod-node-webhook -n "$WEBHOOK_NAMESPACE" --ignore-not-found
kubectl delete service pod-node-webhook -n "$WEBHOOK_NAMESPACE" --ignore-not-found

# Delete all namespaces
print_status "Deleting namespaces..."
for ns in "$WEBHOOK_NAMESPACE" "$TEST_NAMESPACE_1" "$TEST_NAMESPACE_2" "$TEST_NAMESPACE_3"; do
    kubectl delete namespace "$ns" --ignore-not-found
done

print_status "Cleanup completed!" 