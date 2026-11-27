# ShipLift-OpsWarriors
Shipping and Lifting of the services via the containarization.


## Phase 2.1 — AWS ECR Setup

**AWS Region:** `ap-south-1` (Mumbai)

### Private ECR Repositories

- `shoplite/frontend`
- `shoplite/catalog`
- `shoplite/inventory`
- `shoplite/orders`

### Repository Creation

```bash
for service in frontend catalog inventory orders; do
    aws ecr create-repository \
        --repository-name "shoplite/$service" \
        --image-tag-mutability IMMUTABLE \
        --image-scanning-configuration scanOnPush=true
done
```

### Repository Configuration

- Private repositories
- Immutable image tags
- Vulnerability scanning on push enabled
- AES256 encryption at rest
- Lifecycle policy retaining the latest 10 images per repository

### Lifecycle Policy

The reusable lifecycle policy is stored in `infra/ecr/lifecycle-policy.json`.

```bash
for service in frontend catalog inventory orders; do
    aws ecr put-lifecycle-policy \
        --repository-name "shoplite/$service" \
        --lifecycle-policy-text file://infra/ecr/lifecycle-policy.json
done
```

### Verification

```bash
aws ecr describe-repositories --region ap-south-1 --output table
```

AWS CLI authentication uses temporary credentials. No permanent AWS access keys are stored in the repository.


## What this project is

This is a group project for our own learning at *PSEB DevOps Cohort Batch 2*, so we'll do these tasks with the sole purpose of our own learning of DevOps engineering.

This project's code has been provided by [@haroonkhan9426](https://github.com/haroonkhan9426)
