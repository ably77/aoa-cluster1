#!/bin/bash
#set -e

# replace the parameter below with your designated cluster context
# note that the character '_' is an invalid value
#
# please use `kubectl config rename-contexts <current_context> <target_context>` to
# rename your context if necessary
cluster_context="cluster1"
# need to call our mgmt server context to discover LB address
mgmt_context="mgmt"
gloo_mesh_version="2.0.9"
# comma separated list
environment_overlays="cluster-config,infra,apps"

# check to see if defined contexts exist
if [[ $(kubectl config get-contexts | grep ${mgmt_context}) == "" ]] || [[ $(kubectl config get-contexts | grep ${cluster_context}) == "" ]]; then
  echo "Check Failed: Either ${mgmt_context} or ${cluster_context} context does not exist. Please check to see if you have the clusters available"
  echo "Run 'kubectl config get-contexts' to see currently available contexts. If the clusters are available, please make sure that they are named correctly. Default is ${cluster_context}"
  exit 1;
fi

# install argocd
cd bootstrap-argocd
./install-argocd.sh insecure-rootpath ${cluster_context}
cd ..

# wait for argo cluster rollout
./tools/wait-for-rollout.sh deployment argocd-server argocd 20 ${cluster_context}

# deploy app of apps
for i in $(echo ${environment_overlays} | sed "s/,/ /g"); do
  kubectl apply -f environment/${i}/${i}-aoa.yaml --context ${cluster_context}
  sleep 20
done

# register clusters to gloo mesh with helm

until [ "${SVC}" != "" ]; do
  SVC=$(kubectl --context ${mgmt_context} -n gloo-mesh get svc gloo-mesh-mgmt-server -o jsonpath='{.status.loadBalancer.ingress[0].*}')
  echo waiting for gloo mesh management server LoadBalancer IP to be detected
  sleep 2
done

kubectl apply --context ${cluster_context} -f- <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gm-enterprise-agent-${cluster_context}
  namespace: argocd
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: gloo-mesh
  source:
    repoURL: 'https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-agent'
    targetRevision: ${gloo_mesh_version}
    chart: gloo-mesh-agent
    helm:
      valueFiles:
        - values.yaml
      parameters:
        - name: cluster
          value: '${cluster_context}'
        - name: relay.serverAddress
          value: '${SVC}:9900'
        - name: relay.authority
          value: 'gloo-mesh-mgmt-server.gloo-mesh'
        - name: relay.clientTlsSecret.name
          value: 'gloo-mesh-agent-${cluster_context}-tls-cert'
        - name: relay.clientTlsSecret.namespace
          value: 'gloo-mesh'
        - name: relay.rootTlsSecret.name
          value: 'relay-root-tls-secret'
        - name: relay.rootTlsSecret.namespace
          value: 'gloo-mesh'
        - name: rate-limiter.enabled
          value: 'false'
        - name: ext-auth-service.enabled
          value: 'false'
        # enabled for future vault integration
        - name: istiodSidecar.createRoleBinding
          value: 'true'
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
    syncOptions:
    - Replace=true
    - ApplyOutOfSyncOnly=true
  project: default
EOF

# wait for completion of bookinfo install
./tools/wait-for-rollout.sh deployment productpage-v1 bookinfo-frontends 10 ${cluster_context}

# echo port-forward commands
echo
echo "access argocd dashboard:"
echo "kubectl port-forward svc/argocd-server -n argocd 9999:443 --context ${cluster_context}"
echo
echo "navigate to http://localhost:9999/argo in your browser"
echo
echo "username: admin"
echo "password: solo.io"
