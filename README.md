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

## Prerequisites

- Kubernetes cluster
- `kubectl` configured with appropriate permissions
- KUBECONFIG environment variable must be set to point to your cluster's kubeconfig file
  ```bash
  export KUBECONFIG=/path/to/your/kubeconfig
  ```

## Environment Variables

The following environment variable is required:

- `KUBECONFIG`: Path to your cluster's kubeconfig file
  ```bash
  export KUBECONFIG=/path/to/your/kubeconfig
  ```

## Components

- **Mutating Webhook**: Intercepts pod creation requests
- **Webhook Controller**: Processes the requests and enforces node restrictions
- **RBAC**: Required permissions for the webhook to function

## Quick Start

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd mutating-webhook-controller
   ```

2. Set required environment variable:
   ```bash
   export KUBECONFIG=/path/to/your/kubeconfig
   ```

3. Deploy the controller:
   ```bash
   ./test-multi-namespace.sh
   ```

4. Clean up the deployment:
   ```bash
   ./cleanup.sh
   ```

## Testing

The repository includes test pods for both generic and GPU workloads:
- `test-gpu-pod-1.yaml`: GPU pod specification
- `test-gpu-pod-2.yaml`: Additional GPU pod specification

The test script (`test-multi-namespace.sh`) will:
1. Create three namespaces:
   - `restricted-zone-1`: Restricted to a specific node
   - `restricted-zone-2`: Restricted to a different node
   - `unrestricted-zone`: No node restrictions
2. Deploy the webhook in the `webhook-system` namespace
3. Create test pods in all namespaces
4. Verify that pods are scheduled according to namespace restrictions

## Scripts

### test-multi-namespace.sh
- Creates the required namespaces
- Labels namespaces with target nodes
- Deploys the webhook controller and its dependencies
- Creates test pods
- Provides status updates during deployment

### cleanup.sh
- Removes all deployed resources
- Cleans up in the correct order to avoid dependency issues
- Removes all test namespaces

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

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.