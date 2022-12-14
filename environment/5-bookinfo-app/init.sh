#!/bin/bash

echo "wave description:"
echo "deploy bookinfo app"

if [ "${environment_overlay}" == "ocp" ] ; then 
     oc --context ${cluster_context} adm add-scc-to-group anyuid system:serviceaccounts:bookinfo-frontends
     oc --context ${cluster_context} adm policy add-scc-to-group anyuid system:serviceaccounts:bookinfo-backends
  fi