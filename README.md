# AXLearn Aid

Tools to improve productivity around using AXLearn inside of GCP.

Features:
* Script to create GCP resources (GKE cluster, GAR, GCS bucket) and automatically create AXLearn config for created resources.

## Creating the GCP resources required
You can run the following command to bring up GKE cluster, GAR, GCS bucket.

```sh
export CLUSTER=$USER-axlearn
./ensure-gcp-resources.sh
```

The script by default creates a v6e-16 nodepool using spot and a cpu nodepool named
`pathways-head`. The pathways nodepool name needs to exactly match.

An AXLearn config for the resources will be written to
`~/.axlearn.config`.

## Setting up AXLearn

```bash
git clone https://github.com/apple/axlearn.git
cd axlearn
python3.10 -m venv .venv
source .venv/bin/activate
pip install -e '.[core,dev,gcp]'
```

Verify that axlearn has been installed correctly:
```
axlearn gcp launch run --help
```

## Launching a job

Activate the AXLearn config
```sh
axlearn gcp config activate
```

Set the environment variables to match your environment:
```
export CLUSTER=${CLUSTER:-$USER-axlearn}
export BASTION_TIER=disabled
export PROJECT_ID=$(gcloud config get project)
```

Launch an interactive job:
```
axlearn gcp bundle --name=$USER \
        --bundler_spec=allow_dirty=True \
        --bundler_type=artifactregistry \
        --bundler_spec=dockerfile=Dockerfile \
        --bundler_spec=image=tpu \
        --bundler_spec=target=tpu

axlearn gcp launch run --cluster=$CLUSTER \
        --runner_name gke_tpu_single \
        --name=$USER \
        --instance_type=tpu-v6e-16 \
        --num_replicas=1 \
        --bundler_spec=allow_dirty=True \
        --bundler_type=artifactregistry --bundler_spec=image=tpu \
        --bundler_spec=dockerfile=Dockerfile --bundler_spec=target=tpu \
        -- sleep infinity;
```

### Pathways Interactive Supercomputing

Pathways interactive super computing allows you to run your Jax client from
anywhere. The Jax client can now run in a notebook, your VSCode editor or a
Ray job running on CPU.

There are 2 steps:
1. Creating the headless pathways cluster with no Jax client
2. Creating a Jax client that connects to the pathways proxy in the pathways cluster.

#### Creating a Headless Pathways cluster

```
export CLUSTER=$(axlearn gcp config | grep gke_cluster | \
                 awk '{ print $3 }' | tr -d  '"')
axlearn gcp launch run --cluster=$CLUSTER \
        --runner_name gke_tpu_pathways \
        --name=$USER \
        --instance_type=tpu-v6e-16 \
        --num_replicas=1 \
        --bundler_spec=allow_dirty=True \
        --bundler_type=artifactregistry --bundler_spec=image=tpu \
        --bundler_spec=dockerfile=Dockerfile --bundler_spec=target=tpu \
        -- sleep infinity;
```

#### Exposing the Pathways cluster using port-forward

You have to setup something like `kubectl port-forward` to expose the pathways-proxy.

Setup a port-forward to the pathways proxy pod:

```
kubectl get pods -o name | grep "${USER}.*head-0-0.*" | xargs -I{} kubectl port-forward {} 29000:29000
```


#### Running a Jax client from your local CLI


Now run local jax client:
```
export TEST_UNDECLARED_OUTPUTS_DIR=true
JAX_PLATFORMS=proxy JAX_BACKEND_TARGET=grpc://127.0.0.1:29000 \
  python -c 'import pathwaysutils; import jax; import pprint; pathwaysutils.initialize(); pprint.pprint(jax.devices())'
```

#### Running Jax client from VSCode

Create the file `.vscode/launch.json` with the following content in your AXLearn repo:
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Fuji v2 7b flash",
            "type": "debugpy",
            "request": "launch",
            "program": "axlearn/common/launch_trainer_main.py",
            "args": "--module=text.gpt.c4_trainer --config=fuji-7B-v2-flash --trainer_dir=local-train-dir --data_dir=gs://axlearn-public/tensorflow_datasets  --jax_backend=proxy --mesh_selector=tpu-v6e-16",
            "console": "integratedTerminal",
            "env": {
                "JAX_PLATFORMS": "proxy",
                "JAX_BACKEND_TARGET": "grpc://127.0.0.1:29000",
                "PROJECT_ID": "tpu-prod-env-multipod",
                // Uncomment below for more extensive logging.
                // "TF_CPP_MIN_LOG_LEVEL": "0",
                // "TF_CPP_VMODULE": "grpc_host_buffer=3,rpc_helper=3,host_buffer=3,ifrt_backend=3,grpc_service_impl=3",
                "TEST_UNDECLARED_OUTPUTS_DIR": "true",
                "PYDEVD_WARN_SLOW_RESOLVE_TIMEOUT": "30",
            }
        },
    ]
}
```

Inside VSCode AXLearn directory create the `local-train-dir` directory:
```
mkdir -p local-train-dir
```

Now you can go "Run and Debug" and Launch an AXLearn Fuji v2 7B job.


### Launching a regular Fuji/Llama 7B job

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


Now launch a job McJax:
```
axlearn gcp bundle --name=$USER \
        --bundler_spec=allow_dirty=True \
        --bundler_type=artifactregistry \
        --bundler_spec=dockerfile=Dockerfile \
        --bundler_spec=image=tpu \
        --bundler_spec=target=tpu

axlearn gcp launch run --cluster=$CLUSTER \
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

### Launching a Fuji 7B job with Pathways

Launching with Pathways:
```
export CLUSTER=$(axlearn gcp config | grep gke_cluster | \
                 awk '{ print $3 }' | tr -d  '"')
export PROJECT_ID=$(gcloud config get project)
axlearn gcp bundle --name=$USER \
        --bundler_spec=allow_dirty=True \
        --bundler_type=artifactregistry \
        --bundler_spec=dockerfile=Dockerfile \
        --bundler_spec=image=tpu \
        --bundler_spec=target=tpu

axlearn gcp launch run --cluster=$CLUSTER \
        --runner_name gke_tpu_pathways \
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
          --jax_backend=proxy \
          --mesh_selector=tpu-v6e-16 \
          --trace_at_steps=3
```