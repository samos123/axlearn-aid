# Configuring Github action self-hosted runner

1. Create a GKE cluster with an autoscaling spot nodepool for a3-highgpu-1g (scale to 0)
2. Deploy the GitHub self-hosted action K8s Operator Arc using Quickstart

```
NAMESPACE="arc-systems"
helm install arc \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
```

3. Deploy an arc runner set for H100

values-arc-h100.yaml:
```
template:
  spec:
    nodeSelector:
      cloud.google.com/gke-accelerator: nvidia-h100-80gb
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        command: ["/home/runner/run.sh"]
        resources:
          limits:
            nvidia.com/gpu: 1
```

deploy command:
```
INSTALLATION_NAME="arc-runner-h100"
NAMESPACE="arc-runners"
GITHUB_CONFIG_URL="https://github.com/samos123/axlearn"
helm upgrade --install "${INSTALLATION_NAME}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
    --set githubConfigSecret.github_token="${GITHUB_PAT}" \
    -f values-arc-h100.yaml \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

4. Create a github workflow

```
name: AXLearn GKE H100 flash attention test
on:
  schedule:
  - cron: 17 0 * * *
  workflow_dispatch:
    inputs:
      jax_version:
        required: true
        default: '0.5.1'
        type: string
jobs:
  axlearn-flash-attention-h100:
    # You need to use the INSTALLATION_NAME from the previous step
    runs-on: arc-runner-h100
    env:
      PIP_FIND_LINKS: "https://storage.googleapis.com/jax-releases/jax_cuda_releases.html"
      LD_LIBRARY_PATH: "/usr/local/nvidia/lib64"
      JAX_VERSION: ${{ inputs.jax_version }}
    steps:
      - run: ls /usr/local/nvidia/lib64
      - run: ls /usr/local/nvidia/bin
      - run: echo "/usr/local/nvidia/bin" >> "$GITHUB_PATH"
      - run: nvidia-smi
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.10'
          cache: 'pip'
      - run: pip install --upgrade pip
      - run: pip install '.[core,gcp,gpu]'
      # Pin specific Jax version
      - run: pip install --upgrade --force-reinstall "jax[cuda12]==${JAX_VERSION}"
      - run: pip install 'pytest'
      - run: pytest axlearn/common/flash_attention/gpu_attention_test.py
```

Now whenever there is a github action triggered, it will schedule a pod which causes the
nodepool to automatically scale up. So you only pay for 1-2 hours every night.
