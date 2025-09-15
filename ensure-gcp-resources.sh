#!/bin/bash

# --- Configuration & Defaults ---
GKE_CLUSTER_NAME_DEFAULT="${USER}-axlearn" # Default cluster name using system username
GCP_REGION_DEFAULT="us-east5"
GCP_ZONE_DEFAULT="us-east5-b"
CPU_NODE_MACHINE_TYPE="e2-standard-8" # Updated default CPU machine type
CPU_NODE_COUNT_DEFAULT="2" # Default CPU node count
GCP_NETWORK_NAME_DEFAULT="${USER}-net" # Default network name
GCP_SUBNET_NAME_DEFAULT="${USER}-subnet" # Default subnet name
TPU_NODEPOOL_NAME_DEFAULT="tpu-v6e-4x4-pool"
TPU_TOPOLOGY_DEFAULT="4x4"
TPU_NODEPOOL_COUNT_DEFAULT="2" # Default number of nodepools
TPU_MACHINE_TYPE_DEFAULT="ct6e-standard-4t"
TPU_TYPE_LABEL_DEFAULT="tpu-v6e" # Default TPU label for axlearn config
USE_SPOT_TPU_DEFAULT="true" # Default to using Spot VMs for TPUs
AXLEARN_CONFIG_PATH_DEFAULT="$HOME/.axlearn.config" # Use $HOME which bash expands
ARTIFACT_REPO_NAME="axlearn"
ARTIFACT_REPO_LOCATION="us"
JOBSET_VERSION="v0.8.1"

# Use environment variables if set, otherwise use defaults
GKE_CLUSTER_NAME="${GKE_CLUSTER:-$GKE_CLUSTER_NAME_DEFAULT}"
CPU_NODE_COUNT="${CPU_NODE_COUNT:-$CPU_NODE_COUNT_DEFAULT}" # Allow overriding CPU node count
TPU_NODEPOOL_NAME="${TPU_NODEPOOL_NAME:-$TPU_NODEPOOL_NAME_DEFAULT}"
TPU_TOPOLOGY="${TPU_TOPOLOGY:-$TPU_TOPOLOGY_DEFAULT}"
TPU_NODEPOOL_COUNT="${TPU_NODEPOOL_COUNT:-$TPU_NODEPOOL_COUNT_DEFAULT}"
TPU_MACHINE_TYPE="${TPU_MACHINE_TYPE:-$TPU_MACHINE_TYPE_DEFAULT}"
TPU_TYPE_LABEL="${TPU_TYPE_LABEL:-$TPU_TYPE_LABEL_DEFAULT}"
USE_SPOT_TPU="${USE_SPOT_TPU:-$USE_SPOT_TPU_DEFAULT}" # Allow overriding Spot usage
GCP_REGION="${GCP_REGION:-$GCP_REGION_DEFAULT}"
GCP_ZONE="${GCP_ZONE:-$GCP_ZONE_DEFAULT}"
GCP_NETWORK_NAME="${GCP_NETWORK_NAME:-$GCP_NETWORK_NAME_DEFAULT}" # Allow overriding network name
GCP_SUBNET_NAME="${GCP_SUBNET_NAME:-$GCP_SUBNET_NAME_DEFAULT}" # Allow overriding subnet name
AXLEARN_CONFIG_PATH="${AXLEARN_CONFIG_PATH:-$AXLEARN_CONFIG_PATH_DEFAULT}"

# Pathways Head Nodepool Configuration
PATHWAYS_HEAD_NODEPOOL_NAME="pathways-head"
PATHWAYS_HEAD_MACHINE_TYPE="n2-standard-92"
PATHWAYS_HEAD_MIN_NODES=0
PATHWAYS_HEAD_MAX_NODES=10

# Determine Project ID
if [[ -z "$PROJECT_ID" ]]; then
  echo "PROJECT_ID environment variable not set. Attempting to fetch from gcloud config."
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
  if [[ -z "$PROJECT_ID" ]]; then
    echo "Error: Could not determine Project ID. Please set the PROJECT_ID environment variable or configure gcloud."
    exit 1
  fi
  echo "Using Project ID from gcloud config: $PROJECT_ID"
else
  echo "Using Project ID from environment variable: $PROJECT_ID"
fi

# Derived Variables
BUCKET_NAME="gs://${PROJECT_ID}-axlearn"
DOCKER_REPO="${ARTIFACT_REPO_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO_NAME}"
CONFIG_SECTION_HEADER="[gcp.\"$PROJECT_ID:$GCP_ZONE\"]"

echo "--- Ensuring GCP Resources ---"
echo "Project ID:          $PROJECT_ID"
echo "Region:              $GCP_REGION"
echo "Zone:                $GCP_ZONE"
echo "Network:             $GCP_NETWORK_NAME"
echo "Subnet:              $GCP_SUBNET_NAME"
echo "GKE Cluster:         $GKE_CLUSTER_NAME"
echo "CPU Machine Type:    $CPU_NODE_MACHINE_TYPE"
echo "CPU Node Count:      $CPU_NODE_COUNT"
echo "TPU Nodepool Base:   $TPU_NODEPOOL_NAME"
echo "TPU Nodepool Count:  $TPU_NODEPOOL_COUNT"
echo "TPU Machine Type:    $TPU_MACHINE_TYPE"
echo "TPU Type Label:      $TPU_TYPE_LABEL"
echo "TPU Topology:        $TPU_TOPOLOGY"
echo "TPU Use Spot VMs:    $USE_SPOT_TPU"
echo "GCS Bucket:          $BUCKET_NAME"
echo "Artifact Repo:       $ARTIFACT_REPO_NAME @ $ARTIFACT_REPO_LOCATION"
echo "Docker Repo Path:    $DOCKER_REPO"
echo "Jobset Version:      $JOBSET_VERSION"
echo "AXLearn Config Path: $AXLEARN_CONFIG_PATH"
echo "-----------------------------"

# --- VPC Network & Subnet ---
echo "[Network] Checking for network '$GCP_NETWORK_NAME'..."
if ! gcloud compute networks describe "$GCP_NETWORK_NAME" --project "$PROJECT_ID" &> /dev/null; then
  gcloud compute networks create "$GCP_NETWORK_NAME" \
    --project "$PROJECT_ID" \
    --subnet-mode=custom
  echo "[Network] Network '$GCP_NETWORK_NAME' created."
else
  echo "[Network] Network '$GCP_NETWORK_NAME' already exists."
fi

echo "[Subnet] Checking for subnet '$GCP_SUBNET_NAME' in network '$GCP_NETWORK_NAME' region '$GCP_REGION'..."
if ! gcloud compute networks subnets describe "$GCP_SUBNET_NAME" --region "$GCP_REGION" --project "$PROJECT_ID" &> /dev/null; then
  gcloud compute networks subnets create "$GCP_SUBNET_NAME" \
    --project "$PROJECT_ID" \
    --network "$GCP_NETWORK_NAME" \
    --region "$GCP_REGION" \
    --range=10.1.0.0/20 # Default range, adjust if needed
  echo "[Subnet] Subnet '$GCP_SUBNET_NAME' created."
else
  echo "[Subnet] Subnet '$GCP_SUBNET_NAME' already exists."
fi

# --- GKE Cluster & Nodepools ---
echo "[GKE] Checking for cluster '$GKE_CLUSTER_NAME' in region '$GCP_REGION'..."
if ! gcloud container clusters describe "$GKE_CLUSTER_NAME" --region "$GCP_REGION" --project "$PROJECT_ID" &> /dev/null; then
  gcloud container clusters create "$GKE_CLUSTER_NAME" \
    --project "$PROJECT_ID" \
    --region "$GCP_REGION" \
    --machine-type "$CPU_NODE_MACHINE_TYPE" \
    --num-nodes="$CPU_NODE_COUNT" \
    --node-locations "$GCP_ZONE" \
    --network "$GCP_NETWORK_NAME" \
    --subnetwork "$GCP_SUBNET_NAME" \
    --default-max-pods-per-node 31 \
    --enable-ip-alias \
    --enable-dataplane-v2 --enable-ip-alias --enable-multi-networking \
    --scopes "https://www.googleapis.com/auth/cloud-platform" \
    --release-channel=rapid
  echo "[GKE] Cluster '$GKE_CLUSTER_NAME' created."
else
  echo "[GKE] Cluster '$GKE_CLUSTER_NAME' already exists."
fi

for i in $(seq 1 "$TPU_NODEPOOL_COUNT"); do
  CURRENT_TPU_NODEPOOL_NAME="${TPU_NODEPOOL_NAME}-${i}" # e.g., tpu-v6e-4x4-pool-1

  echo "[GKE] Checking for TPU nodepool '$CURRENT_TPU_NODEPOOL_NAME' in cluster '$GKE_CLUSTER_NAME' (Instance $i of $TPU_NODEPOOL_COUNT)..."
  # Check if nodepool exists
  gcloud container node-pools describe "$CURRENT_TPU_NODEPOOL_NAME" --cluster "$GKE_CLUSTER_NAME" --region "$GCP_REGION" --project "$PROJECT_ID" &> /dev/null # Suppress output for check

  if [[ $? -ne 0 ]]; then
    # Calculate num_nodes based on topology (this seems to be per-nodepool)
    # This handles both 2D and 3D topologies.
    IFS='x' read -r -a dims <<< "$TPU_TOPOLOGY"
    total_chips=1
    for dim in "${dims[@]}"; do
      total_chips=$((total_chips * dim))
    done
    # Assuming 4 chips per node for ct5p and ct6e machine types.
    num_nodes=$((total_chips / 4))
    if [[ $num_nodes -eq 0 ]]; then
      num_nodes=1 # Ensure at least one node for topologies smaller than 4 chips.
    fi
    echo "[GKE] Calculated num_nodes: $num_nodes for nodepool '$CURRENT_TPU_NODEPOOL_NAME' based on topology $TPU_TOPOLOGY"

    GCLOUD_NODEPOOL_CREATE_ARGS=(
      "$CURRENT_TPU_NODEPOOL_NAME" # Use the unique name for this instance
      --project "$PROJECT_ID"
      --cluster "$GKE_CLUSTER_NAME"
      --location "$GCP_REGION"
      --node-locations "$GCP_ZONE"
      --num-nodes "$num_nodes"
      --machine-type "$TPU_MACHINE_TYPE"
      --tpu-topology "$TPU_TOPOLOGY"
      --enable-gvnic
      --scopes "https://www.googleapis.com/auth/cloud-platform"
    )

    if [[ "$USE_SPOT_TPU" == "true" ]]; then
      echo "[GKE] Using Spot VMs for TPU nodepool '$CURRENT_TPU_NODEPOOL_NAME'."
      GCLOUD_NODEPOOL_CREATE_ARGS+=(--spot)
    else
      echo "[GKE] Using On-Demand VMs for TPU nodepool '$CURRENT_TPU_NODEPOOL_NAME'."
    fi

    gcloud container node-pools create "${GCLOUD_NODEPOOL_CREATE_ARGS[@]}"
    echo "[GKE] TPU nodepool '$CURRENT_TPU_NODEPOOL_NAME' created."
  else
    echo "[GKE] TPU nodepool '$CURRENT_TPU_NODEPOOL_NAME' already exists."
  fi
done

echo "[GKE] Checking for Pathways Head nodepool '$PATHWAYS_HEAD_NODEPOOL_NAME' in cluster '$GKE_CLUSTER_NAME'..."
# Check if nodepool exists, suppressing output
gcloud container node-pools describe "$PATHWAYS_HEAD_NODEPOOL_NAME" --cluster "$GKE_CLUSTER_NAME" --region "$GCP_REGION" --project "$PROJECT_ID" &> /dev/null
# Create nodepool if the describe command failed (exit status != 0)
if [[ $? -ne 0 ]]; then
  echo "[GKE] Creating Pathways Head nodepool '$PATHWAYS_HEAD_NODEPOOL_NAME'..."
  gcloud container node-pools create "$PATHWAYS_HEAD_NODEPOOL_NAME" \
    --project "$PROJECT_ID" \
    --cluster "$GKE_CLUSTER_NAME" \
    --location "$GCP_REGION" \
    --node-locations "$GCP_ZONE" \
    --machine-type "$PATHWAYS_HEAD_MACHINE_TYPE" \
    --enable-autoscaling \
    --min-nodes "$PATHWAYS_HEAD_MIN_NODES" \
    --max-nodes "$PATHWAYS_HEAD_MAX_NODES" \
    --scopes "https://www.googleapis.com/auth/cloud-platform" \
    --node-labels=axlearn/nodepool_type=workload \
    --network-performance-configs=total-egress-bandwidth-tier=TIER_1
  echo "[GKE] Pathways Head nodepool '$PATHWAYS_HEAD_NODEPOOL_NAME' created."
else
  echo "[GKE] Pathways Head nodepool '$PATHWAYS_HEAD_NODEPOOL_NAME' already exists."
fi

# --- Jobset Controller Installation ---
gcloud container clusters get-credentials "$GKE_CLUSTER_NAME" --region "$GCP_REGION" --project "$PROJECT_ID"

echo "[Jobset] Checking for Jobset CRD..."
if ! kubectl get crd jobsets.jobset.x-k8s.io &> /dev/null; then
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/jobset/releases/download/$JOBSET_VERSION/manifests.yaml
  echo "[Jobset] Jobset controller installed."
else
  echo "[Jobset] Jobset CRD already exists."
fi

# --- GCS Bucket Creation ---
echo "[GCS] Checking for bucket '$BUCKET_NAME'..."
if ! gsutil ls "$BUCKET_NAME" &> /dev/null; then
  gsutil mb -p "$PROJECT_ID" -l "$GCP_REGION" "$BUCKET_NAME"
  echo "[GCS] Bucket '$BUCKET_NAME' created."
else
  echo "[GCS] Bucket '$BUCKET_NAME' already exists."
fi

# --- Artifact Registry Repository Creation ---
echo "[Artifact Registry] Checking for repository '$ARTIFACT_REPO_NAME' in location '$ARTIFACT_REPO_LOCATION'..."
if ! gcloud artifacts repositories describe "$ARTIFACT_REPO_NAME" --location="$ARTIFACT_REPO_LOCATION" --project "$PROJECT_ID" &> /dev/null; then
  gcloud artifacts repositories create "$ARTIFACT_REPO_NAME" \
    --repository-format=docker \
    --location="$ARTIFACT_REPO_LOCATION" \
    --project="$PROJECT_ID"
  echo "[Artifact Registry] Repository '$ARTIFACT_REPO_NAME' created."
else
  echo "[Artifact Registry] Repository '$ARTIFACT_REPO_NAME' already exists."
fi

# --- AXLearn Configuration File Update ---
echo "[AXLearn Config] Ensuring configuration in '$AXLEARN_CONFIG_PATH'..."

# Define the config block content using printf
AXLEARN_CONFIG_BLOCK=$(printf "%s\n" \
  "$CONFIG_SECTION_HEADER" \
  "project = \"$PROJECT_ID\"" \
  "region = \"$GCP_REGION\"" \
  "zone = \"$GCP_ZONE\"" \
  "gke_cluster = \"$GKE_CLUSTER_NAME\"" \
  "cluster = \"$GKE_CLUSTER_NAME\"" \
  "labels = \"$TPU_TYPE_LABEL\"" \
  "docker_repo = \"$DOCKER_REPO\"" \
  "default_dockerfile = \"Dockerfile\"" \
  "permanent_bucket = \"${PROJECT_ID}-axlearn\"" \
  "private_bucket = \"${PROJECT_ID}-axlearn\"" \
  "ttl_bucket = \"${PROJECT_ID}-axlearn\""
)

# Ensure the directory exists (though $HOME should exist)
mkdir -p "$(dirname "$AXLEARN_CONFIG_PATH")"

if [[ -f "$AXLEARN_CONFIG_PATH" ]]; then
  echo "[AXLearn Config] File exists. Checking for section '$CONFIG_SECTION_HEADER'..."
  # Use grep -F for fixed string matching and -q for quiet mode
  if grep -Fq "$CONFIG_SECTION_HEADER" "$AXLEARN_CONFIG_PATH"; then
    echo "[AXLearn Config] Warning: Section '$CONFIG_SECTION_HEADER' already exists in '$AXLEARN_CONFIG_PATH'. Skipping modification. Please review manually."
  else
    # Add a newline before appending if the file doesn't end with one
    [[ $(tail -c1 "$AXLEARN_CONFIG_PATH" | wc -l) -eq 0 ]] && echo "" >> "$AXLEARN_CONFIG_PATH"
    echo "" >> "$AXLEARN_CONFIG_PATH" # Add a blank line for separation
    echo "$AXLEARN_CONFIG_BLOCK" >> "$AXLEARN_CONFIG_PATH"
    echo "[AXLearn Config] Configuration appended."
  fi
else
  echo "$AXLEARN_CONFIG_BLOCK" > "$AXLEARN_CONFIG_PATH"
  echo "[AXLearn Config] Configuration file created."
fi

echo "--- Resource Check Complete ---"
echo "Script finished successfully."
