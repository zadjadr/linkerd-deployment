#!/bin/bash
#
# Prepares Linkerd to any Kubernetes Cluster.

wait_for_certificate() {
  local cert_name="$1"
  local namespace="$2"
  local timeout="300s"

  echo "Waiting for certificate $cert_name to become ready.. (timeout $timeout)"
  kubectl wait --for=condition=Ready "certificate/$cert_name" --timeout=$timeout --namespace "$namespace"
  if [ $? -eq 0 ]; then
    echo "Certificate $cert_name is ready."
  else
    echo "Certificate $cert_name is not ready within the timeout period."
  fi
}

# Check if at least one parameter is provided
if [ $# -lt 1 ]; then
  echo "Prepares Linkerd to any Kubernetes Cluster."
  echo
  echo "Usage: $0 <context> [certificate-dir]"
  echo
  echo "  context:         Required. Name of the Kubernetes Context to use."
  echo "  certificate-dir: Optional. Certificate directory of the root CA certificates. Default: certs"
  echo "                   We assume that there is a 'trustanchor' and 'webhook' directory below the 'certificate-dir'"
  echo "                   and that both of them contain sops encrypted files 'root.asc.crt' and 'root.asc.key'."
  exit 1
fi

context="$1"
certificate_dir="${2:-certs}"

echo "Context Name: $context"
echo "Certificate Directory: $certificate_dir"
echo
read -p "Do you want to continue (y/n)? " answer

if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Exiting..."
    exit 0
fi

sops -d "$certificate_dir/trustanchor/root.asc.crt" > "$certificate_dir/trustanchor/root.crt"
sops -d "$certificate_dir/trustanchor/root.asc.key" > "$certificate_dir/trustanchor/root.key"
sops -d "$certificate_dir/webhooks/root.asc.crt" > "$certificate_dir/webhooks/root.crt"
sops -d "$certificate_dir/webhooks/root.asc.key" > "$certificate_dir/webhooks/root.key"

kubectl config use-context "$context"

kubectl create namespace linkerd
kubectl label namespace linkerd \
  linkerd.io/is-control-plane=true \
  config.linkerd.io/admission-webhooks=disabled \
  linkerd.io/control-plane-ns=linkerd
kubectl annotate namespace linkerd linkerd.io/inject=disabled

kubectl create namespace linkerd-viz
kubectl label namespace linkerd-viz linkerd.io/extension=viz

helm upgrade --install linkerd-crds -n linkerd --create-namespace linkerd/linkerd-crds --atomic

kubectl create secret tls linkerd-trust-anchor \
    --cert="$certificate_dir/trustanchor/root.crt" \
    --key="$certificate_dir/trustanchor/root.key" \
    --namespace=linkerd

kubectl create secret tls webhook-issuer-tls \
    --cert="$certificate_dir/webhooks/root.crt" \
    --key="$certificate_dir/webhooks/root.key" \
    --namespace=linkerd

kubectl create secret tls webhook-issuer-tls \
    --cert="$certificate_dir/webhooks/root.crt" \
    --key="$certificate_dir/webhooks/root.key" \
    --namespace=linkerd-viz

kubectl apply -f issuer.yaml
kubectl apply -f networkpolicies.yaml

# Apply certificates and wait for them in different namespaces
declare -A certificates=(
  ["linkerd"]="certificates.yaml"
  ["linkerd-viz"]="certificates-viz.yaml"
)
for namespace in "${!certificates[@]}"; do
  certs=$(kubectl apply -f "${certificates[$namespace]}" | grep -oE 'certificate\.cert-manager\.io/[a-zA-Z0-9-]+ created' | awk '{print $1}' | cut -d '/' -f 2)

  IFS=$'\n'
  for cert_name in $certs; do
    wait_for_certificate "$cert_name" "$namespace"
  done
done

# Remove the unencrypted secrets
rm "$certificate_dir/trustanchor/root.crt"
rm "$certificate_dir/trustanchor/root.key"
rm "$certificate_dir/webhooks/root.crt"
rm "$certificate_dir/webhooks/root.key"
