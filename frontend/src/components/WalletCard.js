import React from 'react';

const WalletCard = ({ balance, onAddFunds, onSendMoney, onRefresh }) => {
  return (
    <div className="card">
      <div className="wallet-info">
        <div><strong>Available Balance</strong></div>
        <div className="balance">₹{balance.toFixed(2)}</div>
      </div>
      <div className="action-buttons">
        <button className="btn btn-primary" onClick={onAddFunds}>
          Add Funds
        </button>
        <button className="btn btn-success" onClick={onSendMoney}>
          Send Money
        </button>
      </div>
    </div>
  );
};

export default WalletCard;
