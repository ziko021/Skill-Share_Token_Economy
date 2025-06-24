# Skill-Share Token Economy Smart Contract

A decentralized platform for exchanging skills and services using time-based fungible tokens on the Stacks blockchain.

##  Features

- Mint, transfer, and escrow tokens
- User profile creation and skill management
- Service listing with availability toggle
- Token-based service booking system
- Provider reputation via user ratings

- **Name**: SkillTime
- **Symbol**: STT
- **Decimals**: 0
- **Initial Supply**: 1,000,000 STT

##  Key Smart Contract Modules

- **Token Logic**: Minting, transferring, escrow
- **User Profiles**: Skill list, reputation, service stats
- **Services**: Creation, toggling availability, categories
- **Bookings**: Escrowed STT payments, completion tracking
- **Ratings**: Post-service feedback with score updates



Use Clarinet to test the contract:
```bash
clarinet test
```

##  Errors and Validations

| Code | Meaning                     |
|------|-----------------------------|
| 100  | Unauthorized action         |
| 101  | Insufficient balance        |
| 102  | Invalid token amount        |
| 103  | Service not found           |
| 104  | Booking not found           |
| 105  | Already completed           |
| 106  | Invalid booking status      |
| 107  | Cannot book your own service|
| 108  | Invalid rating value (1–5)  |

## Author

- GitHub: [ziko021](https://github.com/ziko021)
- Email: ossaiziko01@gmail.com

## License

MIT License

