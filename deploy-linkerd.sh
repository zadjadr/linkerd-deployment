#!/bin/bash
#
# Deploys Linkerd to any Kubernetes Cluster.

# Check if at least one parameter is provided
if [ $# -lt 1 ]; then
  echo "Deploys Linkerd to any Kubernetes Cluster."
  echo
  echo "Usage: $0 <context> [non-masq-cidr] [certificate-dir]"
  echo
  echo "  context:         Required. Name of the Kubernetes Context to use."
  echo "  non-masq-cidr:   Optional. Non-Masquerading CIDR of the Cluster. Default: 100.64.0.0/10"
  echo "  certificate-dir: Optional. Certificate directory of the root CA certificates. Default: tools/k8s/linkerd/certs"
  echo "                   We assume that there is a 'trustanchor' and 'webhook' directory below the 'certificate-dir'"
  echo "                   and that both of them contain sops encrypted files 'root.asc.crt' and 'root.asc.key'."
  exit 1
fi

context="$1"
# Validation of the CIDR will happen within the linkerd helm chart
non_masq_cidr="${2:-100.64.0.0/10}"
certificate_dir="${3:-certs}"

echo "Context Name: $context"
echo "Non-Masquerade CIDR: $non_masq_cidr"
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

helm upgrade --install linkerd-control-plane \
  -n linkerd --create-namespace \
  --set-file identityTrustAnchorsPEM="$certificate_dir/trustanchor/root.crt" \
  --set identity.issuer.scheme=kubernetes.io/tls \
  --set policyValidator.externalSecret=true \
  --set-file policyValidator.caBundle="$certificate_dir/webhooks/root.crt" \
  --set proxyInjector.externalSecret=true \
  --set-file proxyInjector.caBundle="$certificate_dir/webhooks/root.crt" \
  --set profileValidator.externalSecret=true \
  --set-file profileValidator.caBundle="$certificate_dir/webhooks/root.crt" \
  --set clusterNetworks="$non_masq_cidr" \
  --atomic \
  -f tools/k8s/linkerd/values.yaml \
  linkerd/linkerd-control-plane

# Linkerd Viz
helm upgrade --install linkerd-viz \
  -n linkerd-viz --create-namespace \
  --set tap.externalSecret=true \
  --set-file tap.caBundle="$certificate_dir/webhooks/root.crt" \
  --set tapInjector.externalSecret=true \
  --set-file tapInjector.caBundle="$certificate_dir/webhooks/root.crt" \
  --atomic \
  -f tools/k8s/linkerd/viz.yaml \
  linkerd/linkerd-viz

# Remove the unencrypted secrets
rm "$certificate_dir/trustanchor/root.crt"
rm "$certificate_dir/trustanchor/root.key"
rm "$certificate_dir/webhooks/root.crt"
rm "$certificate_dir/webhooks/root.key"

linkerd check
