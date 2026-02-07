#!/bin/bash

# A script to create a GCS bucket and assign Storage Admin permissions
# to a specific Workload Identity principal set.

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
set -eu

# --- Configuration ---
# You can change this variable if needed.
readonly ROLE_TO_ASSIGN="roles/storage.admin"

# --- Script Logic ---

# 1. Check for required command-line arguments
if [ -z "${2-}" ]; then
  echo "❌ Error: Missing arguments."
  echo "Usage:   ./create_gcs_bucket.sh <bucket-name> <region>"
  echo "Example: ./create_gcs_bucket.sh my-unique-bucket-123 europe-west4"
  exit 1
fi

readonly BUCKET_NAME="$1"
readonly LOCATION="$2"

echo "--- Starting GCS Bucket Setup ---"

# 2. Get the current Project ID from gcloud config
echo "➡️ Fetching active gcloud Project ID..."
readonly PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo "❌ Error: No active gcloud project found."
    echo "Please set one using: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi
echo "✅ Project ID: $PROJECT_ID"

# 3. Get the Project Number using the Project ID
echo "➡️ Fetching Project Number for '$PROJECT_ID'..."
readonly PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
echo "✅ Project Number: $PROJECT_NUMBER"

# 4. Construct the full Workload Identity principal string
readonly PRINCIPAL="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/namespace/default"

echo "➡️ Principal to be granted permissions:"
echo "   $PRINCIPAL"

# 5. Create the GCS bucket
echo "➡️ Creating bucket gs://$BUCKET_NAME in $LOCATION..."
gcloud storage buckets create "gs://$BUCKET_NAME" --location="$LOCATION"

# 6. Add the IAM policy binding to the bucket
echo "➡️ Assigning '$ROLE_TO_ASSIGN' to the principal for gs://$BUCKET_NAME..."
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET_NAME" \
  --member="$PRINCIPAL" \
  --role="$ROLE_TO_ASSIGN"

echo -e "\n🎉 --- Success! --- 🎉"
echo "Bucket 'gs://$BUCKET_NAME' is ready in '$LOCATION' and permissions are set."
