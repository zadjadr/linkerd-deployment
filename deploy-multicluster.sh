#!/bin/bash
#
# Prepares and deploy Linkerd Multi-Cluster functionality.

# Check if at least one parameter is provided
if [ $# -lt 1 ]; then
  echo "Prepares and deploy Linkerd Multi-Cluster functionality."
  echo
  echo "Usage: $0 <context>"
  echo
  echo "  context:         Required. Name of the Kubernetes Context to use."
  exit 1
fi

context="$1"
echo "Context Name: $context"

read -p "Do you want to continue (y/n)? " answer

if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Exiting..."
    exit 0
fi

kubectl config use-context "$context"

kubectl create ns linkerd-multicluster
kubectl annotate namespace linkerd-multicluster linkerd.io/inject=enabled

kubectl apply -f tools/k8s/linkerd/networkpolicies-multicluster.yaml

helm upgrade \
  --install linkerd-multicluster linkerd/linkerd-multicluster \
  -f tools/k8s/linkerd/multicluster.yaml \
  -n linkerd-multicluster --create-namespace

# The linkerd-gateway has issues on its first deployment
# it often can not find the service account and hangs in a crash loop,
# until the replicationset is removed.

DEPLOYMENT_NAME=linkerd-gateway
NAMESPACE=linkerd-multicluster
MAX_WAIT_SECONDS=120
start_time=$(date +%s)

# Check the deployment status for MAX_WAIT_SECONDS
while true; do
  # Calculate the elapsed time
  current_time=$(date +%s)
  elapsed_time=$((current_time - start_time))

  # Check if the elapsed time has exceeded the maximum wait time
  if [ "$elapsed_time" -ge "$MAX_WAIT_SECONDS" ]; then
    echo "Timeout reached. Deleting the replication set..."

    # Find the replication set associated with the deployment
    replication_set=$(kubectl get rs -n "$NAMESPACE" --selector=app="$DEPLOYMENT_NAME" --output custom-columns=NAME:.metadata.name --no-headers)

    # Delete the replication set
    kubectl delete rs "$replication_set" -n "$NAMESPACE"

    echo "Replication set removed."
    exit 1
  fi

  # Check the deployment status
  deployment_status=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')

  # Check if the deployment is available
  if [ "$deployment_status" == "True" ]; then
    echo "Deployment is available."
    exit 0
  else
    echo "Deployment is not available. Checking event logs..."

    # Get the event logs for the deployment
    event_logs=$(kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$DEPLOYMENT_NAME" --output custom-columns=MESSAGE:.message --no-headers)

    # Check if the event logs contain the specific error message
    if echo "$event_logs" | grep -q "serviceaccount not found"; then
      echo "Serviceaccount was not found by the linkerd-gateway. Removing replication set..."

      # Find the replication set associated with the deployment
      replication_set=$(kubectl get rs -n "$NAMESPACE" --selector=app="$DEPLOYMENT_NAME" --output custom-columns=NAME:.metadata.name --no-headers)

      # Delete the replication set
      kubectl delete rs "$replication_set" -n "$NAMESPACE"

      echo "Replication set removed."
      exit 0
    fi
  fi

  # Sleep for a short duration before checking again (e.g., 5 seconds)
  sleep 5
done

linkerd multicluster check
linkerd multicluster gateways
