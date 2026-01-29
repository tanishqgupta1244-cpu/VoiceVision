# Voice Vision

A collection of innovative applications focused on accessibility and financial management.

## Overview

Voice Vision is a multi-project repository containing two distinct applications:

1. **[Digital Wallet](./digital-wallet/)** - A full-stack web application for managing personal finances
2. **[Blind Navigation](./blind-navigation/)** - An iOS accessibility app using AR and ML to assist visually impaired users

## Projects

### Digital Wallet

A modern web-based financial application built with React, Node.js, Express, and MongoDB.

**Key Features:**
- Real-time balance tracking
- Send and receive money
- Transaction history
- Telegram notifications
- RESTful API for iOS app integration

**Tech Stack:** React, Node.js, Express, MongoDB

**Link:** [Digital Wallet README](./digital-wallet/README.md)

---

### Blind Navigation

An iOS accessibility application designed to assist visually impaired users through computer vision and augmented reality.

**Key Features:**
- Real-time object detection
- Text recognition (OCR)
- Indian currency recognition
- QR code scanning with wallet integration
- Voice announcements
- Face ID payment verification

**Tech Stack:** SwiftUI, ARKit, Core ML, Vision

**Link:** [Blind Navigation README](./blind-navigation/README.md)

## Directory Structure

```
voice-vision/
├── digital-wallet/          # React web application
│   ├── frontend/           # React frontend
│   ├── backend/            # Express.js backend
│   └── README.md           # Digital Wallet documentation
├── blind-navigation/        # iOS application
│   ├── blind-navigation/   # Xcode project
│   └── README.md           # Blind Navigation documentation
└── README.md               # This file
```

## Getting Started

Each project is independent and can be run separately. Choose the project you're interested in and follow its specific README:

- For the Digital Wallet web app, see [digital-wallet/README.md](./digital-wallet/README.md)
- For the Blind Navigation iOS app, see [blind-navigation/README.md](./blind-navigation/README.md)

## Prerequisites

### Digital Wallet (Web)
- Node.js (v14+)
- MongoDB
- npm or yarn

### Blind Navigation (iOS)
- macOS
- Xcode (latest version)
- iOS 17.0+ device or simulator

## Development

Each project has its own development environment:

```bash
# Digital Wallet - Backend
cd digital-wallet/backend
npm install
npm start

# Digital Wallet - Frontend
cd digital-wallet/frontend
npm install
npm start

# Blind Navigation - Open in Xcode
cd blind-navigation
open blind-navigation.xcodeproj
```

## Purpose

This repository showcases two different types of applications:

1. **Financial Technology**: Modern web development for managing digital finances
2. **Accessibility Technology**: Mobile development using cutting-edge AR/ML for improving accessibility

## Integration Between Projects

**The Blind Navigation iOS app integrates with the Digital Wallet backend** to enable QR code-based payments for visually impaired users.

### How It Works

1. The Blind Navigation app provides a QR payment mode (activated by long-press)
2. Users scan QR codes and enter payment amounts via voice interface
3. Face ID/Touch ID verification is required for security
4. The iOS app calls the Digital Wallet API to process transactions
5. The web dashboard shows all transactions made through the iOS app

### Setting Up the Integration

To use both apps together:

1. Start the Digital Wallet backend (`cd digital-wallet/backend && npm start`)
2. Run the Digital Wallet frontend (optional, for web access)
3. Update the backend URL in `blind-navigation/blind-navigation/BackendConfig.swift` if needed
4. Run the Blind Navigation iOS app on a device or simulator
5. Activate QR payment mode and scan the configured QR code

For detailed setup instructions, see the individual project READMEs.

## Contributing

Contributions are welcome! Please specify which project you're contributing to when submitting pull requests or issues.

## License

This repository contains open source projects available for educational and practical use. Each project may have its own licensing terms.

## Contact

For questions or feedback about specific projects, please refer to the individual project READMEs.
