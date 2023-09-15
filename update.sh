#!/bin/bash
#
# Updates Linkerd via Helm.
#

if [ $# -lt 2 ]; then
  echo "Updates Linkerd via Helm."
  echo
  echo "Usage: $0 <context> <helm-release-name> [helm-release-namespace]"
  echo
  echo "  context:                Required. Name of the Kubernetes Context to use."
  exit 1
fi

context="$1"

echo "Context Name: $context"
echo
read -p "Do you want to continue (y/n)? " answer

if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Exiting..."
    exit 0
fi


helm repo update

kubectl config use-context "$context"

helm upgrade linkerd-crds \
  --namespace linkerd \
  --atomic \
  --reuse-values

helm upgrade linkerd-control-plane \
  --namespace linkerd \
  --atomic \
  --reuse-values

helm upgrade linkerd-viz \
  --namespace linkerd \
  --atomic \
  --reuse-values
