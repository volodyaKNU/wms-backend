# wms-backend

Node.js/Express API and Docker Compose infrastructure for the WMS individual
project.

## Requirements

- Node.js 20+
- PostgreSQL

## Setup

```bash
npm install
cp .env.example .env
psql "$DATABASE_URL" -f infra/schema.sql
npm start
```

Health check:

```bash
GET /health
```

## Docker Compose

Clone `wms-backend` and `wms-frontend` as sibling folders, then run from the
parent folder:

```bash
docker compose -f wms-backend/infra/docker-compose.yml up -d --build --wait
```

The command starts PostgreSQL, the Express backend, and the Nginx frontend. Open
<http://localhost:5173>; the API health endpoint is available at
<http://localhost:4000/health>.

Stop the stack while keeping database data:

```bash
docker compose -f wms-backend/infra/docker-compose.yml down
```

Add `-v` to also delete the PostgreSQL volume.

API:

```text
GET    /api/products
GET    /api/products/:id
POST   /api/products
PUT    /api/products/:id
DELETE /api/products/:id
POST   /api/products/:id/income
POST   /api/products/:id/writeoff
GET    /api/movements
```

## CI and container image

Pull requests build the full three-container stack and run frontend Cypress
tests. A successful push to `main` publishes
`ghcr.io/volodyaknu/wms-backend:latest` and an immutable image tagged with the
commit SHA.
