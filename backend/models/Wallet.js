const mongoose = require('mongoose');

const walletSchema = new mongoose.Schema({
  balance: {
    type: Number,
    default: 0,
    required: true
  }
}, {
  timestamps: true
});

module.exports = mongoose.model('Wallet', walletSchema);

