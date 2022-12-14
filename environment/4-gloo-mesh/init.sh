#!/bin/bash

echo "wave description:"
echo "deploy and register gloo-mesh agent and addons"

if [ "${environment_overlay}" == "ocp" ] ; then 
     oc --context ${cluster_context} adm policy add-scc-to-group anyuid system:serviceaccounts:gloo-mesh-addons
  fi

# check to see if gloo_mesh_version variable was passed through, if not prompt for it
if [[ ${gloo_mesh_version} == "" ]]
  then
    # provide gloo_mesh_version variable
    echo "Please provide the gloo_mesh_version to use (i.e. 2.1.2):"
    read gloo_mesh_version
fi

# discover gloo mesh endpoint with kubectl
until [ "${SVC}" != "" ]; do
  SVC=$(kubectl --context ${mgmt_context} -n gloo-mesh get svc gloo-mesh-mgmt-server -o jsonpath='{.status.loadBalancer.ingress[0].*}')
  echo waiting for gloo mesh management server LoadBalancer IP to be detected
  sleep 2
done

kubectl apply --context ${mgmt_context} -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: KubernetesCluster
metadata:
  name: cluster1
  namespace: gloo-mesh
  labels:
    roottrust: shared
spec:
  clusterDomain: cluster.local
EOF


if [ "${environment_overlay}" == "ocp" ] ; then 
     kubectl apply --context ${cluster_context} -f- <<EOF
     apiVersion: argoproj.io/v1alpha1
     kind: Application
     metadata:
       name: gm-enterprise-agent-mgmt
       namespace: argocd
     spec:
       destination:
         server: https://kubernetes.default.svc
         namespace: gloo-mesh
       source:
         repoURL: 'https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-agent'
         targetRevision: 2.1.2
         chart: gloo-mesh-agent
         helm:
           skipCrds: true
           parameters:
             - name: cluster
               value: 'mgmt'
             - name: relay.serverAddress
               value: '${SVC}:9900'
             - name: relay.authority
               value: 'gloo-mesh-mgmt-server.gloo-mesh'
             #- name: relay.clientTlsSecret.name
             #  value: 'gloo-agent-tls-cert'
             #- name: relay.clientTlsSecret.namespace
             #  value: 'gloo-mesh'
             - name: ext-auth-service.enabled
               value: 'false'
             - name: rate-limiter.enabled
               value: 'false'
             - name: glooMeshAgent.enabled
               value: 'true'
             - name: glooMeshAgent.floatingUserId
               value: 'true'
             # enabled for future vault integration
             - name: istiodSidecar.createRoleBinding
               value: 'false'
       syncPolicy:
         automated:
           prune: true
           selfHeal: true
         syncOptions:
         - Replace=true
         - ApplyOutOfSyncOnly=true
       project: default
EOF
  else
    # register clusters to gloo mesh with helm
    kubectl apply --context ${cluster_context} -f- <<EOF
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: gm-enterprise-agent-cluster1
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
              value: 'cluster1'
            - name: relay.serverAddress
              value: '${SVC}:9900'
            - name: relay.authority
              value: 'gloo-mesh-mgmt-server.gloo-mesh'
            - name: relay.clientTlsSecret.name
              value: 'gloo-agent-tls-cert'
            - name: relay.clientTlsSecret.namespace
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
  fi

