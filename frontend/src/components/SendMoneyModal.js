import React, { useState } from 'react';

const SendMoneyModal = ({ balance, onClose, onSendMoney }) => {
  const [amount, setAmount] = useState('');
  const [recipientPhone, setRecipientPhone] = useState('');
  const [description, setDescription] = useState('');

  const validateIndianPhoneNumber = (phone) => {
    // Remove spaces and dashes
    const cleaned = phone.replace(/[\s-]/g, '');
    
    // Indian phone number patterns:
    // +91 followed by 10 digits
    // 0 followed by 10 digits
    // Just 10 digits
    const indianPhoneRegex = /^(\+91[6-9]\d{9}|0[6-9]\d{9}|[6-9]\d{9})$/;
    
    return indianPhoneRegex.test(cleaned);
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!amount || parseFloat(amount) <= 0) {
      alert('Please enter a valid amount');
      return;
    }
    if (parseFloat(amount) > balance) {
      alert('Insufficient balance');
      return;
    }
    if (!recipientPhone) {
      alert('Please enter recipient phone number');
      return;
    }
    if (!validateIndianPhoneNumber(recipientPhone)) {
      alert('Please enter a valid Indian phone number\nFormat: +91XXXXXXXXXX or 0XXXXXXXXXX or XXXXXXXXXX (10 digits)');
      return;
    }
    onSendMoney(parseFloat(amount), recipientPhone, description);
    setAmount('');
    setRecipientPhone('');
    setDescription('');
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2>Send Money</h2>
          <button className="close-btn" onClick={onClose}>X</button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label>Recipient Phone Number</label>
            <input
              type="tel"
              className="form-input"
              placeholder="+91XXXXXXXXXX or 0XXXXXXXXXX"
              value={recipientPhone}
              onChange={(e) => setRecipientPhone(e.target.value)}
              required
            />
          </div>
          <div className="form-group">
            <label>Amount</label>
            <input
              type="number"
              className="form-input"
              placeholder="0.00"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              step="0.01"
              min="0"
              max={balance}
              required
            />
            <div className="balance-info">Available balance: ₹{balance.toFixed(2)}</div>
          </div>
          <div className="form-group">
            <label>Description (Optional)</label>
            <input
              type="text"
              className="form-input"
              placeholder="e.g., Lunch payment"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>
          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={onClose}>
              Cancel
            </button>
            <button type="submit" className="btn btn-success">
              Send Money
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default SendMoneyModal;
