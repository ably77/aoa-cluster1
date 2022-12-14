#!/bin/bash

echo "wave description:"
echo "deploy httpbin app"

if [ "${environment_overlay}" == "ocp" ] ; then 
     oc --context ${cluster_context} adm policy add-scc-to-group anyuid system:serviceaccounts:httpbin
  fi