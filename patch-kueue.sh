#!/bin/bash

# The name of the ClusterQueue to patch.
CQ_NAME="cluster-queue"

set -x

# 1. Fetch the current ClusterQueue object as JSON.
echo "🔎 Fetching current ClusterQueue configuration..."
cq_json=$(kubectl get clusterqueue "$CQ_NAME" -o json)

# Check if the ClusterQueue was fetched successfully.
if [[ -z "$cq_json" ]]; then
  echo "❌ Error: ClusterQueue '$CQ_NAME' not found."
  exit 1
fi

# 2. Use jq to extract the TPU and CPU/Memory flavor details.
echo "⚙️  Extracting resource flavor details..."

# Extract details for the TPU flavor.
tpu_flavor_details=$(echo "$cq_json" | jq '.spec.resourceGroups[] | select(.coveredResources[] == "google.com/tpu") | .flavors[0]')
TPU_FLAVOR_NAME=$(echo "$tpu_flavor_details" | jq -r '.name')
TPU_QUOTA=$(echo "$tpu_flavor_details" | jq '.resources[] | select(.name=="google.com/tpu") | .nominalQuota')

# Extract details for the CPU/Memory flavor.
cpu_flavor_details=$(echo "$cq_json" | jq '.spec.resourceGroups[] | select(.coveredResources[] == "cpu") | .flavors[0]')
CPU_FLAVOR_NAME=$(echo "$cpu_flavor_details" | jq -r '.name')
CPU_QUOTA=$(echo "$cpu_flavor_details" | jq '.resources[] | select(.name=="cpu") | .nominalQuota')
MEMORY_QUOTA=$(echo "$cpu_flavor_details" | jq '.resources[] | select(.name=="memory") | .nominalQuota')

# 3. Build the JSON patch using the extracted variables.
echo "🛠️  Building the dynamic patch..."
patch_json=$(jq -n \
  --arg tpu_flavor_name "$TPU_FLAVOR_NAME" \
  --argjson tpu_quota "$TPU_QUOTA" \
  --arg cpu_flavor_name "$CPU_FLAVOR_NAME" \
  --argjson cpu_quota "$CPU_QUOTA" \
  --argjson memory_quota "$MEMORY_QUOTA" \
  '{
    "spec": {
      "resourceGroups": [
        {
          "coveredResources": ["cpu", "memory", "google.com/tpu"],
          "flavors": [
            {
              "name": $cpu_flavor_name,
              "resources": [
                {"name": "cpu", "nominalQuota": $cpu_quota},
                {"name": "memory", "nominalQuota": $memory_quota},
                {"name": "google.com/tpu", "nominalQuota": 0}
              ]
            },
            {
              "name": $tpu_flavor_name,
              "resources": [
                {"name": "cpu", "nominalQuota": 999999999999},
                {"name": "memory", "nominalQuota": "999999999999G"},
                {"name": "google.com/tpu", "nominalQuota": $tpu_quota}
              ]
            }
          ]
        }
      ]
    }
  }')

# 4. Apply the patch.
echo "🚀 Applying the patch to ClusterQueue '$CQ_NAME'..."
echo "$patch_json" | kubectl patch clusterqueue "$CQ_NAME" --type=merge --patch-file /dev/stdin

echo "✅ Done!"
