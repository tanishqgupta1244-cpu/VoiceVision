const express = require('express');
const router = express.Router();
const Wallet = require('../models/Wallet');
const Transaction = require('../models/Transaction');
const { sendTelegramMessage } = require('../services/telegram');

// Initialize wallet if it doesn't exist
async function getOrCreateWallet() {
  let wallet = await Wallet.findOne();
  if (!wallet) {
    wallet = new Wallet({ balance: 0 });
    await wallet.save();
  }
  return wallet;
}

// Get wallet balance
router.get('/balance', async (req, res) => {
  try {
    const wallet = await getOrCreateWallet();
    res.json({ balance: wallet.balance });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Add funds (deposit)
router.post('/add-funds', async (req, res) => {
  try {
    const { amount, description } = req.body;
    
    if (!amount || amount <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    const wallet = await getOrCreateWallet();
    wallet.balance += amount;
    await wallet.save();

    const transaction = new Transaction({
      type: 'deposit',
      amount: amount,
      description: description || 'Add funds'
    });
    await transaction.save();

    // Send Telegram notification
    const message = `💰 <b>Funds Added</b>\n` +
      `Amount: ₹${amount.toFixed(2)}\n` +
      `Description: ${description || 'N/A'}\n` +
      `New Balance: ₹${wallet.balance.toFixed(2)}`;
    await sendTelegramMessage(message);

    res.json({ 
      balance: wallet.balance,
      transaction 
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Send money (withdrawal)
router.post('/send-money', async (req, res) => {
  try {
    const { amount, recipientPhone, description } = req.body;
    
    if (!amount || amount <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    if (!recipientPhone) {
      return res.status(400).json({ error: 'Recipient phone number is required' });
    }

    const wallet = await getOrCreateWallet();
    
    if (wallet.balance < amount) {
      return res.status(400).json({ error: 'Insufficient balance' });
    }

    wallet.balance -= amount;
    await wallet.save();

    const transaction = new Transaction({
      type: 'withdrawal',
      amount: amount,
      recipientPhone: recipientPhone,
      description: description || 'Send money'
    });
    await transaction.save();

    // Send Telegram notification
    const message = `💸 <b>Money Sent</b>\n` +
      `Amount: ₹${amount.toFixed(2)}\n` +
      `To: ${recipientPhone}\n` +
      `Description: ${description || 'N/A'}\n` +
      `New Balance: ₹${wallet.balance.toFixed(2)}`;
    await sendTelegramMessage(message);

    res.json({ 
      balance: wallet.balance,
      transaction 
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get all transactions
router.get('/transactions', async (req, res) => {
  try {
    const transactions = await Transaction.find().sort({ createdAt: -1 });
    res.json(transactions);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Telegram test notification
router.get('/telegram-test', async (req, res) => {
  try {
    if (!process.env.TELEGRAM_BOT_TOKEN || !process.env.TELEGRAM_CHAT_ID) {
      return res.status(400).json({
        error: 'Telegram not configured. Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in .env'
      });
    }

    const message = `✅ <b>Telegram Test</b>\nThis is a test message from the Digital Wallet backend.`;
    const ok = await sendTelegramMessage(message);
    if (!ok) {
      return res.status(500).json({ error: 'Telegram send failed. Check bot token, chat ID, and bot permissions.' });
    }
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;

