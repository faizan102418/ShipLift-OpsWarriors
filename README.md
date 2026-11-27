# ShipLift-OpsWarriors
Shipping and Lifting of the services via the containarization.


## Phase 2.1 — AWS ECR Setup

**AWS Region:** `ap-southeast-2` (Sydney)

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
aws ecr describe-repositories --region ap-southeast-2 --output table
```

AWS CLI authentication uses temporary credentials. No permanent AWS access keys are stored in the repository.


## What this project is

This is a group project for our own learning at *PSEB DevOps Cohort Batch 2*, so we'll do these tasks with the sole purpose of our own learning of DevOps engineering.

This project's code has been provided by [@haroonkhan9426](https://github.com/haroonkhan9426)

## Phase 2 — Production Deployment

### Live Application

https://shoplite-opswarriors.duckdns.org

### Architecture

- Frontend: React and Nginx
- Catalog: Node.js
- Inventory: Go
- Orders: Java
- Database: PostgreSQL 17
- Container registry: AWS ECR
- Production server: AWS EC2, Ubuntu 24.04 LTS
- Automation: GitHub Actions
- AWS authentication: GitHub OIDC and EC2 IAM role

### Deployment Workflow

1. Developers create feature branches and submit pull requests.
2. CI validates Dockerfiles, image sizes and shell scripts.
3. Merging into main triggers the production deployment.
4. GitHub Actions obtains temporary AWS credentials using OIDC.
5. Four application images are built and pushed to ECR.
6. Images are tagged with the short Git commit SHA.
7. Supported images are checked for critical vulnerabilities.
8. GitHub Actions connects to EC2 using restricted SSH.
9. Deployment files are transferred and verified.
10. All required images are pulled before containers are replaced.
11. PostgreSQL and its persistent volume are preserved.
12. Internal and public HTTP smoke tests verify the deployment.

### Manual Image Publishing

Authenticate to AWS using temporary credentials, then run:

    ./scripts/push.sh

### Manual Deployment

On the production server:

    sudo /opt/shoplite/deploy.sh <commit-sha>

### Rollback

Deploy a previously published release:

    sudo /opt/shoplite/deploy.sh <previous-commit-sha>

The deployment script also attempts automatic rollback if a new
release fails its deployment checks.

### HTTPS Configuration

- Host Nginx terminates TLS on port 443.
- Let's Encrypt provides the TLS certificate.
- Certbot manages certificate renewal.
- HTTP redirects to HTTPS.
- Docker frontend binds to 127.0.0.1:8080.
- Public CI/CD smoke tests use HTTPS.
- Certificates remain independent of application containers.

### Security Controls

- Private ECR repositories with immutable tags.
- Lifecycle policies retaining the latest 10 images.
- No permanent AWS access keys required by CI/CD.
- Repository-specific and main-branch-specific OIDC trust.
- Least-privilege IAM policies.
- Dedicated deployment user with restricted SSH commands.
- SSH password authentication and root login disabled.
- SSH host key verification.
- Root-owned deployment files and environment files.
- SHA256 verification of transferred deployment files.
- Backend services and PostgreSQL not publicly exposed.
- Separate frontend and internal backend Docker networks.
- Persistent PostgreSQL volume.

Changes to deploy.sh or db/init.sql require administrator approval
of their SHA256 checksums on the production server.

### Implementation Deviations and Limitations

- Sydney is used because the AWS account restricts Mumbai.
- m7i-flex.large is used due to Free Tier instance eligibility.
- A custom scoped ECR pull policy replaces the managed policy.
- Restricted sudo access replaces Docker group membership.
- SSH port 22 is public for GitHub-hosted runners.
- Inventory uses a scratch image unsupported by ECR Basic Scanning.
  Separate Go vulnerability scanning remains outstanding.
- Application-level authentication remains future work.
- Health endpoints provide basic liveness checks.
- A database backup exists, but full restoration is untested.
- GitHub Actions reports Node.js runtime deprecation warnings.

### Deployment Evidence

See [Phase 2 Acceptance Evidence](docs/evidence/phase2.md).
