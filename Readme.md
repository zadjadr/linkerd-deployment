# Linkerd

Some scripts to deploy Linkerd.

## Prereq.

- [linkerd cli tool](https://linkerd.io/2.14/getting-started/#step-1-install-the-cli) (for checking)
- [step](https://smallstep.com/docs/step-cli) (used in the certificate creation script)
- [sops](https://github.com/getsops/sops) To encrypt and decrypt the certificates
- For Multi-cluster Mesh: Have at least 2 Kubernetes Clusters

To use multiple contexts in the kubeconfig:

```bash
mkdir ~/.kube/creds

CLUSTER1_NAME=cluster1.k8s.local # west
CLUSTER2_NAME=cluster2.k8s.local # east

kops export kubecfg --admin=240h0m0s --name ${CLUSTER1_NAME} --kubeconfig ~/.kube/creds/${CLUSTER1_NAME}.yaml
kops export kubecfg --admin=240h0m0s --name ${CLUSTER2_NAME} --kubeconfig ~/.kube/creds/${CLUSTER2_NAME}.yaml

export KUBECONFIG=${HOME}/.kube/creds/${CLUSTER1_NAME}.yaml:${HOME}/.kube/creds/${CLUSTER2_NAME}.yaml

kubectl config get-contexts

# you should have atleast two contexts now
CURRENT   NAME                  CLUSTER               AUTHINFO              NAMESPACE
*         cluster1.k8s.local    cluster1.k8s.local    cluster1.k8s.local
          cluster2.k8s.local    cluster2.k8s.local    cluster2.k8s.local
```

### Add helm charts

```bash
helm repo add linkerd https://helm.linkerd.io/stable
helm repo update
```

## Install Linkerd Control Plane

- We create our own trust anchor and webhook root CA
- We let Cert-Manager handle renewals of all Certificates based on our CAs
- Having one trust anchor and webhook root CA allows us to share them with other Clusters to create a Multi-Cluster service mesh

### Create CA root certificates

This step needs to be done once and the certificates can be used for multiple clusters.

We could use `openssl`, but [`step`](https://smallstep.com/docs/step-cli) is recommended.

```bash
# Creates all needed certificates for a Linkerd deployment.
#
# Usage: tools/k8s/linkerd/create-certs.sh [OPTIONS]
# Options:
#   -h, --help              Display this help message
#   -d, --certificate-dir   Certificate directory of the root CA certificates. (default: tools/k8s/linkerd/certs)
#                           We assume that there is a 'trustanchor' and 'webhook' directory below the 'certificate-dir'
#                           and that both of them contain sops encrypted files 'root.asc.crt' and 'root.asc.key'.

tools/k8s/linkerd/create-certs.sh
```

### Deploy Linkerd

```bash
# Prepares Linkerd to any Kubernetes Cluster.

# Usage: tools/k8s/linkerd/prepare-linkerd.sh <context> [certificate-dir]

#   context:         Required. Name of the Kubernetes Context to use.
#   certificate-dir: Optional. Certificate directory of the root CA certificates. Default: tools/k8s/linkerd/certs
#                    We assume that there is a 'trustanchor' and 'webhook' directory below the 'certificate-dir'
#                    and that both of them contain sops encrypted files 'root.asc.crt' and 'root.asc.key'.
tools/k8s/linkerd/prepare-linkerd.sh ${CLUSTER1_NAME}
tools/k8s/linkerd/prepare-linkerd.sh ${CLUSTER2_NAME}


# Deploys Linkerd to any Kubernetes Cluster.
#
# Usage: tools/k8s/linkerd/deploy-linkerd.sh <context> [non-masq-cidr] [certificate-dir]
#
#   context:         Required. Name of the Kubernetes Context to use.
#   non-masq-cidr:   Optional. Non-Masquerading CIDR of the Cluster. Default: 100.64.0.0/10
#   certificate-dir: Optional. Certificate directory of the root CA certificates. Default: tools/k8s/linkerd/certs
#                    We assume that there is a 'trustanchor' and 'webhook' directory below the 'certificate-dir'
#                    and that both of them contain sops encrypted files 'root.asc.crt' and 'root.asc.key'.

tools/k8s/linkerd/deploy-linkerd.sh ${CLUSTER1_NAME}
# If you use a non default non masq. cidr - eg. 100.128.0.0/10
tools/k8s/linkerd/deploy-linkerd.sh ${CLUSTER2_NAME} "100.128.0.0/10"
```

### Update Linkerd

```bash
# Updates Linkerd via Helm.
#
# Usage: tools/k8s/linkerd/update.sh <context> <helm-release-name> [helm-release-namespace]
#
#   context:                Required. Name of the Kubernetes Context to use.
#   helm-release-name:      Name of the Helm release to update.
#   helm-release-namespace: Optional. Namespace of the Helm release to update. Default: Same as helm-release-name.
  
tools/k8s/linkerd/update.sh ${CLUSTER_NAME} linkerd-control-plane linkerd
tools/k8s/linkerd/update.sh ${CLUSTER_NAME} linkerd-viz
```

## Install Linkerd Multicluster

See [the docs](https://linkerd.io/2.14/tasks/installing-multicluster/)

We will follow the docs mentioned, I will only add some extra information, if really needed (e.g. troubleshooting).

### Step 1

```bash
# Prepares and deploy Linkerd Multi-Cluster functionality.
#
# Usage: tools/k8s/linkerd/deploy-multicluster.sh <context>
#
#   context:         Required. Name of the Kubernetes Context to use.

tools/k8s/linkerd/deploy-multicluster.sh ${CLUSTER1_NAME}
tools/k8s/linkerd/deploy-multicluster.sh ${CLUSTER2_NAME}
```

### Step 2

Link the clusters:

```bash
# Link any amount of Kubernetes Clusters via Linkerd Multi-Cluster linking.
#
# Usage: tools/k8s/linkerd/link-multicluster.sh context1 context2 [context3] [context4] [contextN...]
#
#   At least 2 available Kubernetes contexts must be provided.

tools/k8s/linkerd/link-multicluster.sh ${CLUSTER1_NAME} ${CLUSTER2_NAME}
```

### Step 3 Running the test resource (optional)

```bash
# West
kubectl --context=${CLUSTER1_NAME} apply \
  -n test -k tools/k8s/linkerd/test/west

kubectl --context=${CLUSTER1_NAME} -n test \
  rollout status deploy/podinfo || break

# East
kubectl --context=${CLUSTER2_NAME} apply \
  -n test -k tools/k8s/linkerd/test/east

kubectl --context=${CLUSTER2_NAME} -n test \
  rollout status deploy/podinfo || break
```

### Step 4 Exposing the services (optional)

```bash
# Export podinfo service on both sides
kubectl --context=${CLUSTER1_NAME} label svc -n test podinfo mirror.linkerd.io/exported=true
kubectl --context=${CLUSTER2_NAME} label svc -n test podinfo mirror.linkerd.io/exported=true

# Test that it works
kubectl --context=${CLUSTER1_NAME} -n test exec -c nginx -it \
  $(kubectl --context=${CLUSTER1_NAME} -n test get po -l app=frontend \
    --no-headers -o custom-columns=:.metadata.name) \
  -- /bin/sh -c "apk add curl traceroute && curl http://podinfo-cluster2-k8s-local:9898"

kubectl --context=${CLUSTER2_NAME} -n test exec -c nginx -it \
  $(kubectl --context=${CLUSTER2_NAME} -n test get po -l app=frontend \
    --no-headers -o custom-columns=:.metadata.name) \
  -- /bin/sh -c "apk add curl && curl http://podinfo-cluster1-k8s-local:9898"
```


## Mesh namespaces and pods

To mesh a namespace or workload, add the `linkerd.io/inject=enabled` to them.

```bash
NAMESPACE_NAME=test
kubectl annotate namespace $NAMESPACE_NAME linkerd.io/inject=enabled
```

If there are workloads in the namespace already, restart the workloads so the new identity is loaded.


## Add PodMonitoring (when using Kube-Prometheus Stack)

```bash
kubectl apply -f tools/k8s/linkerd/podmonitors.yaml
```

### Add Grafana Dashboards

```bash
k apply -f tools/k8s/linkerd/grafana-dashboard.yaml
```
