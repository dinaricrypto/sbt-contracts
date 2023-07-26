# Proof of Reserve Overview

The Proof of Reserve is a protocol developed by Chainlink that enables reliable monitoring of reserve assets. This protocol provides an on-chain data feed that can be accessed directly for verifications. In the context of the Dinari protocol, the Proof of Reserve system plays a crucial role in maintaining stringent oversight of assets.

In case an anomaly is detected in an asset, the Proof of Reserve system responds promptly by enforcing the strictest possible protective measures on the corresponding pool. This mechanism is vital for maintaining the protocol's integrity and stability, thereby providing a high level of trust and security for all participants.

This repository contains the essential smart contracts for the implementation of the Proof of Reserve mechanism within the Dinari protocol. These contracts have been carefully developed to ensure smooth integration with the Dinari protocol, enabling optimal asset protection.

![Proof of Reserve Diagram](https://github.com/dinaricrypto/sbt-contracts/blob/Josue-Guessennd/CU-8684vx5mv-Transparency-Page---Chainlink-proof-of-reserves/src/proof-of-reserve/proof-of-reserve.png?raw=true)

# How It Works

Our application enables users to purchase blockchain-based shares of traditional stocks, such as Apple's AAPL. For each share purchased in the real world, we create a digital equivalent (e.g., AAPL.d), bridging the gap between traditional stock markets and the blockchain. This repository provides the necessary transparency by proving that we own the asset corresponding to the tokens we issue.

The Proof of Reserve is implemented through two main contracts: `ProofOfReserveExecutor` and `ProofOfReserveAggregator`.

## ProofOfReserveExecutor

This contract manages the list of assets that need to be verified for reserve proof. It utilizes the `ProofOfReserveAggregator` to verify whether the reserves for these assets are fully backed. The contract's responsibilities include enabling and disabling assets for checking.

## ProofOfReserveAggregator

This contract serves as a decentralized aggregator of proof of reserve data. It leverages Chainlink price feed oracles to ascertain whether certain assets are fully reserved. The contract's responsibilities include enabling and disabling the Chainlink oracle feeds for different assets.

# Data Flow

Here's a step-by-step guide to the process:

1. A user interacts with the application to verify whether the assets are fully backed.
2. The request to verify the assets is sent to the `ProofOfReserveExecutor` contract.
3. The `ProofOfReserveExecutor` contract communicates with the `ProofOfReserveAggregator` contract, forwarding the addresses of the assets to be checked.
4. The `ProofOfReserveAggregator` contract interacts with the respective Chainlink oracle for each asset.
5. Each Chainlink oracle retrieves data from the custodian's API, confirming the presence of the real-world assets backing the digital tokens.
6. The Chainlink oracle sends the result back to the `ProofOfReserveAggregator` contract.
7. The `ProofOfReserveAggregator` contract compiles the results and sends them back to the `ProofOfReserveExecutor` contract.
8. The `ProofOfReserveExecutor` contract determines whether the assets are fully backed based on the aggregated results and returns a boolean value.
9. The result is finally returned to the user.