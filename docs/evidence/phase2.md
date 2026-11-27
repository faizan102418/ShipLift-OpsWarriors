# Phase 2 — Deployment and Acceptance Evidence

Date: 27 November 2026

## Deployment Summary

- Project: ShipLift-OpsWarriors / ShopLite
- AWS region: ap-southeast-2 (Sydney)
- EC2 instance type: m7i-flex.large
- Operating system: Ubuntu 24.04 LTS
- Domain: shoplite-opswarriors.duckdns.org
- Elastic IP: 3.105.154.136
- Verified release: 1ca7e5b
- Previous release: fdb13a8

## GitHub Actions

- Pull request: #5
- Workflow run: 45955025353
- Final result: Success
- Successful jobs: 5/5
- Reported runtime: 2 minutes 6 seconds

Workflow:
https://github.com/faizan102418/ShipLift-OpsWarriors/actions/runs/45955025353

The initial deployment failed because the IAM trust policy used
the legacy OIDC subject format. Updating it to GitHub's immutable
repository subject resolved the authentication failure.

## ECR Verification

All four private repositories contain the verified release tag.

| Repository | Tag |
|---|---|
| shoplite/frontend | 1ca7e5b |
| shoplite/catalog | 1ca7e5b |
| shoplite/inventory | 1ca7e5b |
| shoplite/orders | 1ca7e5b |

Image digests:

Frontend:
sha256:59ca1427a4e48114137a35b13bf59dd80842f9144825a476d3bfe5db44126ef9

Catalog:
sha256:38cac6c91ee9fd69d5ee168193af145a1aca647d178c4cb6e9d19eff0147b7c3

Inventory:
sha256:c8837bd00e1effa6ffa61007117cf1b5b3096a1c61166a7ad8884884ab86162a

Orders:
sha256:0a3be3b7add68fd8037562b0eb15373674e4abc2ecd430cbb76af9e34c5dfd2c

## Acceptance Tests

| Test | Observed result | Status |
|---|---|---|
| CI validation | Six successful checks | PASS |
| OIDC authentication | Temporary AWS credentials | PASS |
| ECR publishing | Four matching release tags | PASS |
| Automated EC2 deployment | Exact commit SHA | PASS |
| Container health | Five healthy containers | PASS |
| Frontend | HTTP 200 | PASS |
| Catalog health | HTTP 200 | PASS |
| Inventory health | HTTP 200 | PASS |
| Orders health | HTTP 200 | PASS |
| Catalog products | Three products returned | PASS |
| Inventory persistence | Keyboard stock remains 18 | PASS |
| Order persistence | Order ID 1 retained | PASS |
| Direct IP access | Empty reply | PASS |
| Catalog port 3000 | Connection timed out | PASS |
| Inventory port 8081 | Connection timed out | PASS |
| Orders port 8082 | Connection timed out | PASS |
| PostgreSQL port 5432 | Connection timed out | PASS |
| Host external listeners | Ports 22 and 80 only | PASS |
| PostgreSQL preservation | Same container and start time | PASS |
| Persistent storage | pgdata retained | PASS |
| Manual rollback | Previous release restored successfully | PASS |

## Database Persistence

PostgreSQL container ID:
4c7f681416dfc0ab2156e3ec2e63e78d16516dfd1020feb4af955354123c16be

Started:
2026-11-26T18:51:14.456108032Z

Persistent volume: pgdata

Existing order after automated deployment:

- Order ID: 1
- Product ID: 1
- Quantity: 2
- Total: 9000.00
- Remaining Keyboard stock: 18

The PostgreSQL container was not recreated during application
deployment. Existing data remained available.

## Vulnerability Verification

The frontend, catalog and orders images passed the automated
ECR critical-vulnerability gate.

Inventory's scratch-based image is unsupported by ECR Basic
Scanning. Separate Go vulnerability scanning is pending.

## Known Limitations

See the Implementation Deviations and Limitations section in README.md.

This evidence records the demonstrated deployment and acceptance
checks. It does not claim full production hardening or verification
of every possible failure scenario.

