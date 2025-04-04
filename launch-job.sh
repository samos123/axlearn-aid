#!/usr/bin/env bash

set -xe

export RANDOM_CHARS=$(LC_CTYPE=C openssl rand -base64 12 | tr -dc 'a-z0-9' | head -c 3 ; echo)
export CLUSTER=${CLUSTER:-$USER-axlearn2}
export NAME=$USER-$RANDOM_CHARS
export BASTION_TIER=disabled
export DEFAULT_PROJECT_ID=$(gcloud config get project)
export PROJECT_ID=${PROJECT_ID:-$DEFAULT_PROJECT_ID}

axlearn gcp bundle --name=$NAME \
        --bundler_spec=allow_dirty=True \
        --bundler_type=artifactregistry --bundler_spec=image=tpu \
        --bundler_spec=dockerfile=Dockerfile --bundler_spec=target=tpu

axlearn gcp gke start --cluster=$CLUSTER --name=$NAME \
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
