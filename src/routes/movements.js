const express = require('express');
const db = require('../db');

const router = express.Router();

router.get('/', async (req, res, next) => {
  try {
    const result = await db.query(
      `SELECT m.id,
              m.product_id,
              p.sku,
              p.name AS product_name,
              m.type,
              m.quantity,
              m.created_at
       FROM movements m
       JOIN products p ON p.id = m.product_id
       ORDER BY m.created_at DESC, m.id DESC`
    );

    res.json(result.rows);
  } catch (error) {
    next(error);
  }
});

module.exports = router;
