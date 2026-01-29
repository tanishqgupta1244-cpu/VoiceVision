import React, { useState } from 'react';

const AddFundsModal = ({ onClose, onAddFunds }) => {
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [selectedQuickAmount, setSelectedQuickAmount] = useState(null);

  const quickAmounts = [10, 25, 50, 100, 500, 1000];

  const handleQuickSelect = (quickAmount) => {
    setAmount(quickAmount.toString());
    setSelectedQuickAmount(quickAmount);
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!amount || parseFloat(amount) <= 0) {
      alert('Please enter a valid amount');
      return;
    }
    onAddFunds(parseFloat(amount), description);
    setAmount('');
    setDescription('');
    setSelectedQuickAmount(null);
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2>Add Funds</h2>
          <button className="close-btn" onClick={onClose}>X</button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label>Amount</label>
            <input
              type="number"
              className="form-input"
              placeholder="0.00"
              value={amount}
              onChange={(e) => {
                setAmount(e.target.value);
                setSelectedQuickAmount(null);
              }}
              step="0.01"
              min="0"
              required
            />
          </div>
          <div className="form-group">
            <label>Quick Select</label>
            <div className="quick-select">
              {quickAmounts.map((quickAmount) => (
                <button
                  key={quickAmount}
                  type="button"
                  className={`quick-select-btn ${
                    selectedQuickAmount === quickAmount ? 'selected' : ''
                  }`}
                  onClick={() => handleQuickSelect(quickAmount)}
                >
                  ₹{quickAmount}
                </button>
              ))}
            </div>
          </div>
          <div className="form-group">
            <label>Description (Optional)</label>
            <input
              type="text"
              className="form-input"
              placeholder="e.g., Monthly budget"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>
          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={onClose}>
              Cancel
            </button>
            <button type="submit" className="btn btn-primary">
              Add Funds
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default AddFundsModal;
