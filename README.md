# AXLearn Aid

Tools to improve productivity around using AXLearn inside of GCP.

Features:
* Script to create GCP resources (GKE cluster, GAR, GCS bucket) and create an axlearn config
* Apply needed patches to AXLearn so it works on both on-demand and spot

## Creating the GCP resources required
You can run the following command to bring up GKE cluster, GAR, GCS bucket.

```sh
export GKE_CLUSTER_NAME=$USER-axlearn
./ensure-gcp-resources.sh
```

## Launching a job

Activate the AXLearn config
```sh
axlearn gcp config activate
```

Modify the training config for Fuji 7B in `fuji.py` to set global batch size to 32:
```diff
diff --git a/axlearn/experiments/text/gpt/fuji.py b/axlearn/experiments/text/gpt/fuji.py
index dc95d61..7f6fab4 100644
--- a/axlearn/experiments/text/gpt/fuji.py
+++ b/axlearn/experiments/text/gpt/fuji.py
@@ -374,7 +374,7 @@ def get_trainer_kwargs(
             ),
             learner_kwargs=dict(peak_lr=3e-4, weight_decay=0.1),
             max_sequence_length=max_sequence_length,
-            train_batch_size=train_batch_size,
+            train_batch_size=32,
             max_step=max_step,
             mesh_shape=mesh_shape_from_axes(data=-1, fsdp=8),
             mesh_rules=(
```


Now launch a job:
```
export CLUSTER=${CLUSTER:-$USER-axlearn1}
export BASTION_TIER=disabled

axlearn gcp launch --cluster=$CLUSTER \
        --runner_name gke_tpu_single \
        --name=$USER \
        --instance_type=tpu-v6e-16 \
        --num_replicas=1 \
        --bundler_spec=allow_dirty=True \
        --bundler_type=artifactregistry --bundler_spec=image=tpu \
        --bundler_spec=dockerfile=Dockerfile --bundler_spec=target=tpu \
        -- python3 -m axlearn.common.launch_trainer_main \
        --module=text.gpt.c4_trainer --config=fuji-7B-v2-flash \
          --trainer_dir=gs://$PROJECT_ID-axlearn/$USER-v6e-7b-1/ \
          --data_dir=gs://axlearn-public/tensorflow_datasets  \
          --jax_backend=tpu \
          --mesh_selector=tpu-v6e-16 \
          --trace_at_steps=3
```

## Configuring Github action self-hosted runner

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
