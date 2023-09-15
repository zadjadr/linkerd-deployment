#!/bin/bash
#
# Link any amount of Kubernetes Clusters via Linkerd Multi-Cluster linking,

# Check if there are at least 2 required parameters
if [ $# -lt 2 ]; then
  echo "Link any amount of Kubernetes Clusters via Linkerd Multi-Cluster linking."
  echo
  echo "Usage: $0 context1 context2 [context3] [context4] [contextN...]"
  echo
  echo "  At least 2 available Kubernetes contexts must be provided."
  exit 1
fi

# Extract the clusters into an array
clusters=("$@")

# Loop through each cluster and generate the desired output
for cluster1 in "${clusters[@]}"; do
  for cluster2 in "${clusters[@]}"; do
    if [ "$cluster1" != "$cluster2" ]; then
      echo "Linking $cluster1 with $cluster2"
      echo

      linkerd --context=${cluster1} \
        multicluster link --cluster-name ${cluster1//./-} | kubectl --context=${cluster2} apply -f -

      linkerd --context=${cluster1} multicluster check
    fi
  done
done
