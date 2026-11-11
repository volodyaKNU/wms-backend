const express = require('express');
const cors = require('cors');
const prometheus = require('@prometheus-io/client');
const db = require('./db');
const productsRouter = require('./routes/products');
const movementsRouter = require('./routes/movements');

const app = express();
const port = process.env.PORT || 4000;

prometheus.collectDefaultMetrics({ prefix: 'wms_' });

const httpRequestDuration = new prometheus.Histogram({
  name: 'wms_http_request_duration_seconds',
  help: 'Duration of WMS HTTP requests in seconds.',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});

app.use((req, res, next) => {
  const stopTimer = httpRequestDuration.startTimer();

  res.on('finish', () => {
    const route = req.route ? `${req.baseUrl}${req.route.path}` : 'unmatched';
    stopTimer({
      method: req.method,
      route,
      status_code: String(res.statusCode),
    });
  });

  next();
});

app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.get('/health/ready', async (req, res) => {
  try {
    await db.query('SELECT 1');
    res.json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ status: 'not ready' });
  }
});

app.get('/metrics', async (req, res, next) => {
  try {
    res.set('Content-Type', prometheus.register.contentType);
    res.end(await prometheus.register.metrics());
  } catch (error) {
    next(error);
  }
});

app.use('/api/products', productsRouter);
app.use('/api/movements', movementsRouter);

app.use((error, req, res, next) => {
  if (error.code === '23505') {
    return res.status(409).json({ error: 'SKU already exists' });
  }

  const status = error.status || 500;
  const message = status === 500 ? 'Internal server error' : error.message;

  return res.status(status).json({ error: message });
});

if (require.main === module) {
  app.listen(port, () => {
    console.log(`WMS backend listening on port ${port}`);
  });
}

module.exports = app;
