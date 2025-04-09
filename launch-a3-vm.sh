#!/usr/bin/env bash

# Create a spot a3-highpu-8g VM in us-central1-a
# ensure latest NVIDIA drivers are installed

# Define VM properties
VM_NAME="stoelinga-a3-spot-vm-$(date +%s)"
ZONE="us-central1-a"
MACHINE_TYPE="a3-highgpu-8g"
IMAGE_FAMILY="tf-latest-gpu-ubuntu-2204" # Using Ubuntu 22.04 LTS with NVIDIA drivers
IMAGE_PROJECT="deeplearning-platform-release"

echo "Creating A3 spot VM named ${VM_NAME} in ${ZONE}..."

gcloud compute instances create "${VM_NAME}" \
    --zone="${ZONE}" \
    --machine-type="${MACHINE_TYPE}" \
    --provisioning-model=SPOT \
    --instance-termination-action=DELETE \
    --image-family="${IMAGE_FAMILY}" \
    --image-project="${IMAGE_PROJECT}" \
    --boot-disk-size=500GB \
    --maintenance-policy=TERMINATE \
    --scopes=https://www.googleapis.com/auth/cloud-platform

echo "VM ${VM_NAME} created."
