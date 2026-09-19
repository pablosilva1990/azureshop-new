const path = require('node:path');
const express = require('express');
const helmet = require('helmet');
const config = require('./config');
const aiClient = require('./ai/client');
const { calculateShipping, getCoupon, normalizeCep } = require('../public/checkout-utils');
const { normalizeCustomerSessionId } = require('./orders');

function createApp(repository) {
  const app = express();
  app.set('trust proxy', 1); // correto detecção de protocolo/IP atrás do proxy do App Service
  app.use(helmet({ contentSecurityPolicy: false }));
  app.use(express.json({ limit: '100kb' }));
  app.use(express.static(path.resolve(__dirname, '../public')));

  app.get('/api/health', async (_req, res) => {
    try {
      await repository.health();
      res.json({ status: 'ok', application: 'Imersão Arquiteto Azure — Cloud & AI', database: repository.provider, ai: config.aiEnabled });
    } catch { res.status(503).json({ status: 'unhealthy' }); }
  });
  app.get('/api/products', async (_req, res, next) => {
    try { res.json(await repository.listProducts()); } catch (error) { next(error); }
  });
  app.post('/api/orders', async (req, res, next) => {
    try {
      const { customerName, customerEmail, items, couponCode, paymentMethod } = req.body;
      if (!customerName?.trim() || !/^\S+@\S+\.\S+$/.test(customerEmail || '') || !Array.isArray(items) || !items.length) {
        return res.status(400).json({ error: 'Informe nome, e-mail válido e ao menos um item.' });
      }
      const customerSessionId = normalizeCustomerSessionId(req.body.customerSessionId);
      if (!customerSessionId) return res.status(400).json({ error: 'Sessão do cliente inválida.' });
      const cep = normalizeCep(req.body.cep);
      if (calculateShipping(cep) === null) {
        return res.status(400).json({ error: 'Informe um CEP válido para calcular o frete.' });
      }
      const normalizedCoupon = typeof couponCode === 'string' ? couponCode.trim() : '';
      if (normalizedCoupon && !getCoupon(normalizedCoupon)) {
        return res.status(400).json({ error: 'Cupom inválido ou expirado.' });
      }
      const order = await repository.createOrder({
        customerName: customerName.trim(),
        customerEmail: customerEmail.trim(),
        items,
        cep,
        couponCode: getCoupon(normalizedCoupon)?.code || null,
        paymentMethod,
        customerSessionId
      });
      res.status(201).json(order);
    } catch (error) { next(error); }
  });
  app.get('/api/orders', async (req, res, next) => {
    try {
      const customerSessionId = normalizeCustomerSessionId(req.get('x-customer-session-id'));
      if (!customerSessionId) return res.status(401).json({ error: 'Sessão do cliente necessária.' });
      res.json(await repository.listOrders({
        customerSessionId,
        status: typeof req.query.status === 'string' ? req.query.status : '',
        search: typeof req.query.search === 'string' ? req.query.search : ''
      }));
    } catch (error) { next(error); }
  });
  app.get('/api/orders/:orderNumber', async (req, res, next) => {
    try {
      const customerSessionId = normalizeCustomerSessionId(req.get('x-customer-session-id'));
      if (!customerSessionId) return res.status(401).json({ error: 'Sessão do cliente necessária.' });
      const order = await repository.getOrder({ orderNumber: req.params.orderNumber, customerSessionId });
      if (!order) return res.status(404).json({ error: 'Pedido não encontrado.' });
      res.json(order);
    } catch (error) { next(error); }
  });
  app.post('/api/ai/recommendations', async (req, res, next) => {
    if (!config.aiEnabled) return res.status(501).json({ error: 'Integração com Azure AI Foundry será habilitada na etapa de AI.' });
    if (!aiClient.isConfigured()) return res.status(503).json({ error: 'Conector de AI habilitado, mas endpoint/credenciais não configurados.' });
    try {
      const interest = typeof req.body?.interest === 'string' ? req.body.interest : '';
      const products = await repository.listProducts();
      const result = await aiClient.recommend({ products, interest });
      res.json(result);
    } catch (error) { next(error); }
  });
  app.get('/orders', (_req, res) => res.sendFile(path.resolve(__dirname, '../public/index.html')));
  app.get('/orders/:orderNumber', (_req, res) => res.sendFile(path.resolve(__dirname, '../public/index.html')));
  app.use('/api', (_req, res) => res.status(404).json({ error: 'Recurso não encontrado.' }));
  app.use((error, _req, res, _next) => {
    console.error(error);
    res.status(error.status || 500).json({ error: error.status ? error.message : 'Erro interno.' });
  });
  return app;
}

module.exports = { createApp };
