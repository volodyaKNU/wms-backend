const express = require('express');
const productsService = require('../services/products');

const router = express.Router();

function validateProductPayload(req, res, next) {
  const { sku, name, unit, quantity = 0, min_quantity = 0 } = req.body;

  if (!sku || !name || !unit) {
    return res.status(400).json({ error: 'sku, name and unit are required' });
  }

  if (!Number.isInteger(Number(quantity)) || Number(quantity) < 0) {
    return res.status(400).json({ error: 'quantity must be a non-negative integer' });
  }

  if (!Number.isInteger(Number(min_quantity)) || Number(min_quantity) < 0) {
    return res.status(400).json({ error: 'min_quantity must be a non-negative integer' });
  }

  return next();
}

router.get('/', async (req, res, next) => {
  try {
    const products = await productsService.listProducts(req.query.search || '');
    res.json(products);
  } catch (error) {
    next(error);
  }
});

router.get('/:id', async (req, res, next) => {
  try {
    const product = await productsService.getProduct(req.params.id);

    if (!product) {
      return res.status(404).json({ error: 'Product not found' });
    }

    return res.json(product);
  } catch (error) {
    return next(error);
  }
});

router.post('/', validateProductPayload, async (req, res, next) => {
  try {
    const product = await productsService.createProduct(req.body);
    res.status(201).json(product);
  } catch (error) {
    next(error);
  }
});

router.put('/:id', validateProductPayload, async (req, res, next) => {
  try {
    const product = await productsService.updateProduct(req.params.id, req.body);

    if (!product) {
      return res.status(404).json({ error: 'Product not found' });
    }

    return res.json(product);
  } catch (error) {
    return next(error);
  }
});

router.delete('/:id', async (req, res, next) => {
  try {
    const deleted = await productsService.deleteProduct(req.params.id);

    if (!deleted) {
      return res.status(404).json({ error: 'Product not found' });
    }

    return res.status(204).send();
  } catch (error) {
    return next(error);
  }
});

router.post('/:id/income', async (req, res, next) => {
  try {
    const product = await productsService.addMovement(
      req.params.id,
      'income',
      req.body.quantity
    );
    res.json(product);
  } catch (error) {
    next(error);
  }
});

router.post('/:id/writeoff', async (req, res, next) => {
  try {
    const product = await productsService.addMovement(
      req.params.id,
      'writeoff',
      req.body.quantity
    );
    res.json(product);
  } catch (error) {
    next(error);
  }
});

module.exports = router;
