# Workloads

This directory contains training job definitions and inference service manifests that are deployed via ArgoCD.

## Structure

```
workloads/
  training-jobs/     # PyTorchJob, MPIJob definitions
  inference/         # Inference service deployments
```

## Usage

Add workload manifests here and ArgoCD will automatically sync them to the target clusters.
