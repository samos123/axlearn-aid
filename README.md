# AXLearn Aid

Tools to improve productivity around using AXLearn inside of GCP.

Features:
* Script to create GCP resources (GKE cluster and nodepools, GAR, GCS bucket) and create an axlearn config
* Apply needed patches to AXLearn so it works on on-demand or spot

## Creating the GCP resources required

```sh
./ensure-gcp-resources.sh
```

