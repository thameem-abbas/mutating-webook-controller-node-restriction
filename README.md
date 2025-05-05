# Mutating Webhook Controller for Node Restriction

NOTE: This was written using AI and validated by me in exactly one scenario. Please validate this code before using it in production.
NOTE: This is a work in progress and will be updated to support more scenarios.

This project implements a Kubernetes mutating webhook controller that enforces node restrictions for pods based on namespace labels. It ensures that pods in labeled namespaces are scheduled only on specific nodes as configured in the namespace labels.

## Overview

The controller implements the following functionality:
- Intercepts pod creation requests
- Checks if the pod's namespace has a target node label
- If a target node is specified and the pod has no existing node selectors, ensures the pod is scheduled on that node
- Preserves any pre-existing node selectors on pods, allowing manual node selection to take precedence
- Allows pods in unlabeled namespaces to be scheduled normally

## Namespace Configuration

To restrict pods in a namespace to a specific node, label the namespace with `node.restriction/target=<node-name>`. The node name should match the `kubernetes.io/hostname` of the target node.

Example:
```bash
# Label a namespace to restrict pods to a specific node
kubectl label namespace my-namespace node.restriction/target=worker-node-1

# Verify the label was applied
kubectl get namespace my-namespace --show-labels

# Remove the restriction by removing the label
kubectl label namespace my-namespace node.restriction/target-
```

To find available node names:
```bash
kubectl get nodes --show-labels | grep kubernetes.io/hostname
```

## Prerequisites

- Kubernetes cluster
- `kubectl` configured with appropriate permissions
- KUBECONFIG environment variable must be set to point to your cluster's kubeconfig file
  ```bash
  export KUBECONFIG=/path/to/your/kubeconfig
  ```

## Quick Start

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd mutating-webhook-controller
   ```

2. Deploy the webhook controller:
   ```bash
   ./webhook-setup.sh deploy
   ```

3. Deploy test resources (optional):
   ```bash
   ./webhook-test.sh deploy
   ```

4. Clean up resources (in this order):
   ```bash
   # First, clean up test resources (pods and test namespaces)
   ./webhook-test.sh cleanup
   
   # Then, clean up the webhook controller and its resources
   ./webhook-setup.sh cleanup
   ```

## Testing

The test script (`webhook-test.sh`) will:
1. Create three namespaces:
   - `restricted-zone-1`: Restricted to a specific node
   - `restricted-zone-2`: Restricted to a different node
   - `unrestricted-zone`: No node restrictions
2. Create test pods in all namespaces
3. Verify that pods are scheduled according to namespace restrictions

The repository includes test pods for both generic and GPU workloads:
- `test-gpu-pod-1.yaml`: GPU pod specification
- `test-gpu-pod-2.yaml`: Additional GPU pod specification

## Troubleshooting

If you encounter issues:

1. Check the webhook pod logs:
   ```bash
   kubectl logs -n webhook-system -l app=pod-node-webhook
   ```

2. Verify the webhook configuration:
   ```bash
   kubectl get mutatingwebhookconfiguration pod-node-webhook -o yaml
   ```

3. Check pod scheduling status:
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   ```

## Security Considerations

- The webhook uses TLS for secure communication
- RBAC is configured with minimal required permissions
- The controller runs with a dedicated service account

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.