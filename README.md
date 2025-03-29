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

Apply the following patch:
```sh
git apply remove-node-selector.patch
```

Now launch a job:
```
BASTION_TIER=1 axlearn gcp gke start --cluster=$USER-axlearn \
        --instance_type=tpu-v6e-16 \
        --num_replicas=1 \
        --bundler_spec=allow_dirty=True \
        --bundler_type=artifactregistry --bundler_spec=image=tpu \
        --bundler_spec=dockerfile=Dockerfile --bundler_spec=target=tpu \
        -- python3 -m axlearn.common.launch_trainer_main \
        --module=text.gpt.c4_trainer --config=fuji-7B-v2-flash-single-host \
          --trainer_dir=gs://$PROJECT_ID-axlearn/$USER-v6e-7b-1/ \
          --data_dir=gs://axlearn-public/tensorflow_datasets  \
          --jax_backend=tpu \
          --mesh_selector=tpu-v6e-16 \
          --trace_at_steps=3
```