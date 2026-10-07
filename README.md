# wms-backend

Simple WMS backend for Lab 2 individual task.

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

## Docker

From the parent folder that contains both `wms-backend` and `wms-frontend`:

```bash
docker compose up --build
```

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
