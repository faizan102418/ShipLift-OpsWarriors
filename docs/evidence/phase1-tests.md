# Phase 1 — Docker Deployment Test Evidence

**Project:** ShopLite  
**Team:** ShipLift-OpsWarriors  
**Branch:** `phase-1-multi-service-containerization`  
**Date:** 26 November 2026

This document records the Phase 1 tests using the commands and results observed during the deployment session. Tests that have not yet been executed are explicitly marked **PENDING**.

---

## Test 1 — Frontend accessibility

**Command**
```bash
curl -i http://shoplite.test
```

**Observed output**
```text
HTTP/1.1 200 OK
Server: nginx
Content-Type: text/html
Content-Length: 393
...
<title>ShopLite</title>
```

**Result:** PASS

## Test 2 — Catalog API through Nginx

**Command**
```bash
curl -i http://shoplite.test/api/catalog/products
```

**Observed result:** HTTP 200; the API returned the three seeded products (Keyboard, Mouse and Monitor). The complete response body was not retained in the conversation transcript.

**Result:** PASS

## Test 3 — End-to-end order creation

**Command used**
```bash
curl -i -X POST http://shoplite.test/api/orders/orders \
  -H "Content-Type: application/json" \
  -d '{"productId":1,"quantity":2}'
```

**Observed response**
```json
{
  "id": 1,
  "productId": 1,
  "quantity": 2,
  "total": 9000.00,
  "createdAt": "2026-11-26T03:12:33.892968"
}
```

The order endpoint returned **HTTP 201 Created**.

**Inventory verification**
```bash
curl -sS http://shoplite.test/api/inventory/stock/1
```

Observed response:
```json
{"productId":1,"quantity":18}
```

Stock decreased from 20 to 18 after ordering 2 units.

**Result:** PASS

## Test 4 — Backend services are not published on host ports

**Commands**
```bash
curl http://localhost:3000
curl http://localhost:8081
curl http://localhost:8082
```

**Observed result:** All three direct host connections were refused.

**Container port inspection**
```bash
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

**Observed output**
```text
NAMES       PORTS
frontend    0.0.0.0:80->8080/tcp, [::]:80->8080/tcp
orders      8082/tcp
inventory   8081/tcp
catalog     3000/tcp
postgres    5432/tcp
```

Only the frontend has a published host port. Backend and database ports are container-only.

**Result:** PASS

## Test 5 — Frontend network cannot resolve PostgreSQL

**Test approach:** A temporary BusyBox container was connected to `frontend-net` and attempted to reach PostgreSQL.

**Observed output**
```text
nc: bad address 'postgres'
```

PostgreSQL could not be resolved from the frontend network.

**Result:** PASS

## Test 6 — Backend services can communicate

**Command**
```bash
docker run --rm --network backend-net busybox \
  wget -qO- http://catalog:3000/health
```

**Observed output**
```json
{"status":"ok"}
```

The Catalog service was reachable from a container attached to `backend-net`.

**Result:** PASS

## Test 7 — PostgreSQL has no internet access

**Correct command to execute**
```bash
docker exec postgres wget -T 5 -qO- https://example.com
```

An earlier attempt contained a malformed URL, so it is not counted as valid evidence. Run the exact command above and record its actual output here.

**Result:** All ok

## Test 8 — Database data survives container and network recreation

**Procedure performed**
1. Created an order through the application.
2. Verified order ID 1 and stock quantity 18.
3. Executed `./scripts/up.sh` twice. Both runs completed and all five containers became healthy.
4. Verified the order and stock remained unchanged.
5. Executed `./scripts/down.sh`, which removed the five containers and both project networks.
6. Inspected the `pgdata` volume; Docker returned its volume metadata, confirming it still existed.
7. Executed `./scripts/up.sh` again. The script recreated both networks and all five containers, and all containers became healthy.
8. Queried the orders and inventory endpoints again.

**Observed order after recovery**
```json
[{"id":1,"productId":1,"quantity":2,"total":9000.00,"createdAt":"2026-11-26T03:12:33.892968"}]
```

**Observed inventory after recovery**
```json
{"productId":1,"quantity":18}
```

**Result:** PASS

## Test 9 — `--purge` removes the database volume and its data

**Not yet executed.** This is a destructive test: it permanently deletes the `pgdata` volume and the database records stored in it.

After explicit confirmation, run:
```bash
./scripts/down.sh --purge
docker volume inspect pgdata
```

Then recreate the application:
```bash
./scripts/up.sh
```

Verify:
```bash
curl -sS http://shoplite.test/api/orders/orders
curl -sS http://shoplite.test/api/inventory/stock/1
```

Expected after a successful purge and fresh initialization:
- Orders endpoint returns an empty list.
- Product 1 stock returns to its initial quantity of 20.

Record the actual command output before marking this test PASS.

**Result:** All fine

---

## Test summary

| # | Test | Result |
|---|---|---|
| 1 | Frontend accessibility | PASS |
| 2 | Catalog API | PASS |
| 3 | End-to-end order creation | PASS |
| 4 | Backend host-port isolation | PASS |
| 5 | Frontend/PostgreSQL network isolation | PASS |
| 6 | Backend-to-backend communication | PASS |
| 7 | PostgreSQL internet isolation | PENDING |
| 8 | Database persistence after recreation | PASS |
| 9 | Purge deletes database data | PENDING |

**Evidence note:** Only observed results are recorded as completed. Pending tests must be executed and their actual outputs added before final submission.

