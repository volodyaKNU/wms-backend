const db = require('../db');

function toPositiveInteger(value, fieldName) {
  const number = Number(value);

  if (!Number.isInteger(number) || number <= 0) {
    const error = new Error(`${fieldName} must be a positive integer`);
    error.status = 400;
    throw error;
  }

  return number;
}

async function listProducts(search = '') {
  const normalizedSearch = `%${search.trim()}%`;
  const result = await db.query(
    `SELECT id, sku, name, unit, quantity, min_quantity
     FROM products
     WHERE $1 = '%%'
        OR sku ILIKE $1
        OR name ILIKE $1
     ORDER BY id DESC`,
    [normalizedSearch]
  );

  return result.rows;
}

async function getProduct(id) {
  const result = await db.query(
    `SELECT id, sku, name, unit, quantity, min_quantity
     FROM products
     WHERE id = $1`,
    [id]
  );

  return result.rows[0] || null;
}

async function createProduct(product) {
  const result = await db.query(
    `INSERT INTO products (sku, name, unit, quantity, min_quantity)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id, sku, name, unit, quantity, min_quantity`,
    [
      product.sku,
      product.name,
      product.unit,
      Number(product.quantity || 0),
      Number(product.min_quantity || 0),
    ]
  );

  return result.rows[0];
}

async function updateProduct(id, product) {
  const result = await db.query(
    `UPDATE products
     SET sku = $1,
         name = $2,
         unit = $3,
         quantity = $4,
         min_quantity = $5
     WHERE id = $6
     RETURNING id, sku, name, unit, quantity, min_quantity`,
    [
      product.sku,
      product.name,
      product.unit,
      Number(product.quantity || 0),
      Number(product.min_quantity || 0),
      id,
    ]
  );

  return result.rows[0] || null;
}

async function deleteProduct(id) {
  const result = await db.query(
    'DELETE FROM products WHERE id = $1 RETURNING id',
    [id]
  );

  return result.rowCount > 0;
}

async function addMovement(productId, type, quantityValue) {
  const quantity = toPositiveInteger(quantityValue, 'quantity');
  const client = await db.connect();

  try {
    await client.query('BEGIN');

    const productResult = await client.query(
      `SELECT id, sku, name, unit, quantity, min_quantity
       FROM products
       WHERE id = $1
       FOR UPDATE`,
      [productId]
    );

    const product = productResult.rows[0];

    if (!product) {
      const error = new Error('Product not found');
      error.status = 404;
      throw error;
    }

    if (type === 'writeoff' && product.quantity < quantity) {
      const error = new Error('Not enough stock for writeoff');
      error.status = 400;
      throw error;
    }

    const nextQuantity =
      type === 'income' ? product.quantity + quantity : product.quantity - quantity;

    const updatedResult = await client.query(
      `UPDATE products
       SET quantity = $1
       WHERE id = $2
       RETURNING id, sku, name, unit, quantity, min_quantity`,
      [nextQuantity, productId]
    );

    await client.query(
      `INSERT INTO movements (product_id, type, quantity)
       VALUES ($1, $2, $3)`,
      [productId, type, quantity]
    );

    await client.query('COMMIT');
    return updatedResult.rows[0];
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  listProducts,
  getProduct,
  createProduct,
  updateProduct,
  deleteProduct,
  addMovement,
};
