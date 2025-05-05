#!/bin/bash

set -e

# Check if KUBECONFIG is set
if [ -z "$KUBECONFIG" ]; then
    echo "Error: KUBECONFIG environment variable is not set"
    exit 1
fi

WEBHOOK_NAMESPACE="webhook-system"

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
    print_status "Waiting for webhook pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=pod-node-webhook -n "$WEBHOOK_NAMESPACE" --timeout=60s
}

function deploy_webhook() {
    print_status "Deploying webhook components..."

    # Create namespace
    check_namespace "$WEBHOOK_NAMESPACE"

    # Create service account
    print_status "Creating service account..."
    kubectl apply -f service-account.yaml -n "$WEBHOOK_NAMESPACE"

    # Create cluster role
    print_status "Creating cluster role..."
    kubectl apply -f cluster-role.yaml

    # Create cluster role binding
    print_status "Creating cluster role binding..."
    kubectl apply -f cluster-role-binding.yaml

    # Create webhook configuration first
    print_status "Creating webhook configuration..."
    kubectl apply -f webhook-configuration.yaml

    # Generate certificates
    print_status "Generating certificates..."
    ./generate-certs.sh

    # Create deployment
    print_status "Creating deployment..."
    kubectl apply -f deployment.yaml -n "$WEBHOOK_NAMESPACE"

    # Create service
    print_status "Creating service..."
    kubectl apply -f service.yaml -n "$WEBHOOK_NAMESPACE"

    # Wait for pods to be ready
    wait_for_pods

    print_status "Webhook deployment completed successfully!"
}

function cleanup_webhook() {
    print_status "Cleaning up webhook resources..."

    # Delete webhook configuration
    print_status "Deleting webhook configuration..."
    kubectl delete -f webhook-configuration.yaml --ignore-not-found=true

    # Delete cluster role binding
    print_status "Deleting cluster role binding..."
    kubectl delete -f cluster-role-binding.yaml --ignore-not-found=true

    # Delete cluster role
    print_status "Deleting cluster role..."
    kubectl delete -f cluster-role.yaml --ignore-not-found=true

    # Delete deployment
    print_status "Deleting deployment..."
    kubectl delete -f deployment.yaml -n "$WEBHOOK_NAMESPACE" --ignore-not-found=true

    # Delete service
    print_status "Deleting service..."
    kubectl delete -f service.yaml -n "$WEBHOOK_NAMESPACE" --ignore-not-found=true

    # Delete service account
    print_status "Deleting service account..."
    kubectl delete -f service-account.yaml -n "$WEBHOOK_NAMESPACE" --ignore-not-found=true

    # Delete namespace
    print_status "Deleting namespace..."
    kubectl delete namespace "$WEBHOOK_NAMESPACE" --ignore-not-found=true

    print_status "Webhook cleanup completed successfully!"
}

# Main script logic
case "$1" in
    "deploy")
        deploy_webhook
        ;;
    "cleanup")
        cleanup_webhook
        ;;
    *)
        echo "Usage: $0 {deploy|cleanup}"
        exit 1
        ;;
esac 