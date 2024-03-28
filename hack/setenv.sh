#!/bin/bash

function workflowNamespace {
  default="sonataflow-infra"
  read -p "Enter workflow namespace (default: $default): " value

  if [ -z "$value" ]; then
      workflow_namespace="$default"
  else
      workflow_namespace="$value"
  fi
  echo "export WORKFLOW_NAMESPACE=$workflow_namespace" > .env
}

function k8sUrl {
  url="$(oc whoami --show-server)"
  echo "export K8S_CLUSTER_URL=$url" >> .env
}

function k8sToken {
  sa_namespace="orchestrator"
  sa_name="orchestrator"
  read -p "In which namespace we have or have to create the SA holding the persistent token? (default: $sa_namespace): " selected_ns
  if [ -n "$sa_namespace" ]; then
    sa_namespace="$sa_namespace"
  fi

  read -p "What is the name of the SA? (default: $sa_name): " selected_name
  if [ -n "$selected_name" ]; then
    sa_name="$selected_name"
  fi

  if oc get namespace "$sa_namespace" &> /dev/null; then
    echo "Namespace '$sa_namespace' already exists."
  else
    echo "Namespace '$sa_namespace' does not exist. Creating..."
    oc create namespace "$sa_namespace"
  fi

  if oc get sa -n "$sa_namespace" $sa_name &> /dev/null; then
    echo "ServiceAccount '$sa_name' already exists in '$sa_namespace'."
  else
    echo "ServiceAccount '$sa_name' does not exist in '$sa_namespace'. Creating..."
    oc create sa "$sa_name" -n "$sa_namespace"
  fi

  oc adm policy add-cluster-role-to-user cluster-admin -z $sa_name -n $sa_namespace
  echo "Added cluster-admin role to '$sa_name' in '$sa_namespace'."
  token_secret=$(oc get secret -o name -n $sa_namespace | grep ${sa_name}-token)
  token=$(oc get -n $sa_namespace ${token_secret} -o yaml | yq '.data.token' | sed 's/"//g' | base64 -d)
  echo "export K8S_CLUSTER_TOKEN=$token" >> .env
}

function gitToken {
  read -s -p "Enter GitHub access token: " value
  echo ""
  echo "export GITHUB_TOKEN=$value" >> .env
}

function argoCdNamespace {
  default="orchestrator-gitops"
  read -p "Enter ArgoCD installation namespace (default: $default): " value

  if [ -z "$value" ]; then
      argocd_namespace="$default"
  else
      argocd_namespace="$value"
  fi
  echo "export ARGOCD_NAMESPACE=$argocd_namespace" >> .env
}

function argoCdRoute {
  argocd_instances=$(oc get argocd -n "$argocd_namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

  if [ -z "$argocd_instances" ]; then
      echo "No ArgoCD instances found in namespace $argocd_namespace."
      exit 1
  fi

  echo "Select an ArgoCD instance:"
  select instance in $argocd_instances; do
      if [ -n "$instance" ]; then
          selected_instance="$instance"
          break
      else
          echo "Invalid selection. Please choose a valid option."
      fi
  done

  argocd_route=$(oc get route -n $argocd_namespace -l app.kubernetes.io/managed-by=$selected_instance -ojsonpath='{.items[0].status.ingress[0].host}')
  echo "Found Route at $argocd_route"
  echo "export ARGOCD_URL=https://$argocd_route" >> .env
  echo 
}

function argoCdCreds {
  admin_password=$(oc get secret -n $argocd_namespace ${selected_instance}-cluster -ojsonpath='{.data.admin\.password}' | base64 -d)
  echo "export ARGOCD_USERNAME=admin" >> .env
  echo "export ARGOCD_PASSWORD=$admin_password" >> .env
}

function checkPrerequisite {
  if ! command -v yq &> /dev/null; then
    echo "yq is required for this script to run. Exiting."
    exit 1
  fi
}

checkPrerequisite
workflowNamespace
k8sUrl
k8sToken
gitToken
argoCdNamespace
argoCdRoute
argoCdCreds

cat .env



