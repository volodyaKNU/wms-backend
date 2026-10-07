const express = require('express');
const cors = require('cors');
const productsRouter = require('./routes/products');
const movementsRouter = require('./routes/movements');

const app = express();
const port = process.env.PORT || 4000;

app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
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
