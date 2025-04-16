#!/usr/bin/env bash

NAMESPACE="arc-systems"
helm install arc \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller


# CPU arc runners
# TODO remove this just used for auth test
# INSTALLATION_NAME="arc-runner-set"
# NAMESPACE="arc-runners"
# GITHUB_CONFIG_URL="https://github.com/samos123/axlearn"
# helm install "${INSTALLATION_NAME}" \
#     --namespace "${NAMESPACE}" \
#     --create-namespace \
#     --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
#     --set githubConfigSecret.github_token="${GITHUB_PAT}" \
#     oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set

INSTALLATION_NAME="arc-runner-h100"
NAMESPACE="arc-runners"
GITHUB_CONFIG_URL="https://github.com/samos123/axlearn"
helm install "${INSTALLATION_NAME}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
    --set githubConfigSecret.github_token="${GITHUB_PAT}" \
    -f values-arc-h100.yaml \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
