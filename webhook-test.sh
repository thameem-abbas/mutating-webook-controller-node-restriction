#!/bin/bash

set -e

# Check if KUBECONFIG is set
if [ -z "$KUBECONFIG" ]; then
    echo "Error: KUBECONFIG environment variable is not set"
    exit 1
fi

# Test namespaces
TEST_NAMESPACE_1="restricted-zone-1"
TEST_NAMESPACE_2="restricted-zone-2"
TEST_NAMESPACE_3="unrestricted-zone"

# Target nodes (update these with your actual node names)
TARGET_NODE_1="psap-dev-dagray-1xl4-z2-fdkxq"
TARGET_NODE_2="psap-dev-dagray-1xl4-z2-gwwb2"

function print_status() {
    echo "==> $1"
}

function check_namespace() {
    if ! kubectl get namespace "$1" &>/dev/null; then
        print_status "Creating namespace $1..."
        kubectl create namespace "$1"
    fi
}

function wait_for_pods() {
    local namespace=$1
    print_status "Waiting for pods in namespace $namespace to be ready..."
    kubectl wait --for=condition=ready pod -l app=nginx -n "$namespace" --timeout=60s || true
    kubectl wait --for=condition=ready pod -l app=gpu-test -n "$namespace" --timeout=60s || true
}

function deploy_test_resources() {
    print_status "Deploying test resources..."

    # Create test namespaces
    check_namespace "$TEST_NAMESPACE_1"
    check_namespace "$TEST_NAMESPACE_2"
    check_namespace "$TEST_NAMESPACE_3"

    # Label restricted namespaces
    print_status "Labeling restricted namespaces..."
    kubectl label namespace "$TEST_NAMESPACE_1" node.restriction/target="$TARGET_NODE_1" --overwrite
    kubectl label namespace "$TEST_NAMESPACE_2" node.restriction/target="$TARGET_NODE_2" --overwrite

    # Create test pods in all namespaces
    print_status "Creating test pods..."

    # Generic workload pods
    print_status "Creating generic workload pods..."
    kubectl apply -f test-gpu-pod-1.yaml -n "$TEST_NAMESPACE_1"
    kubectl apply -f test-gpu-pod-1.yaml -n "$TEST_NAMESPACE_2"
    kubectl apply -f test-gpu-pod-1.yaml -n "$TEST_NAMESPACE_3"

    # GPU workload pods
    print_status "Creating GPU workload pods..."
    kubectl apply -f test-gpu-pod-2.yaml -n "$TEST_NAMESPACE_1"
    kubectl apply -f test-gpu-pod-2.yaml -n "$TEST_NAMESPACE_2"
    kubectl apply -f test-gpu-pod-2.yaml -n "$TEST_NAMESPACE_3"

    # Wait for pods to be ready
    wait_for_pods "$TEST_NAMESPACE_1"
    wait_for_pods "$TEST_NAMESPACE_2"
    wait_for_pods "$TEST_NAMESPACE_3"

    print_status "Test resources deployed successfully!"
    print_status "Checking pod status and node assignments..."
    echo
    echo "Pods in $TEST_NAMESPACE_1:"
    kubectl get pods -n "$TEST_NAMESPACE_1" -o wide
    echo
    echo "Pods in $TEST_NAMESPACE_2:"
    kubectl get pods -n "$TEST_NAMESPACE_2" -o wide
    echo
    echo "Pods in $TEST_NAMESPACE_3:"
    kubectl get pods -n "$TEST_NAMESPACE_3" -o wide
}

function cleanup_test_resources() {
    print_status "Cleaning up test resources..."

    # Delete pods from all test namespaces
    print_status "Deleting pods..."
    kubectl delete pod --all -n "$TEST_NAMESPACE_1" --ignore-not-found=true
    kubectl delete pod --all -n "$TEST_NAMESPACE_2" --ignore-not-found=true
    kubectl delete pod --all -n "$TEST_NAMESPACE_3" --ignore-not-found=true

    # Delete test namespaces
    print_status "Deleting test namespaces..."
    kubectl delete namespace "$TEST_NAMESPACE_1" --ignore-not-found=true
    kubectl delete namespace "$TEST_NAMESPACE_2" --ignore-not-found=true
    kubectl delete namespace "$TEST_NAMESPACE_3" --ignore-not-found=true

    print_status "Test resources cleanup completed successfully!"
}

# Main script logic
case "$1" in
    "deploy")
        deploy_test_resources
        ;;
    "cleanup")
        cleanup_test_resources
        ;;
    *)
        echo "Usage: $0 {deploy|cleanup}"
        exit 1
        ;;
esac 