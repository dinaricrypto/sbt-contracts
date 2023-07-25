SBT Contracts
================

[![codecov](https://codecov.io/gh/dinaricrypto/sbt-contracts/branch/main/graph/badge.svg?token=6GFOt4AsfI)](https://codecov.io/gh/dinaricrypto/sbt-contracts)

Usage
------
### Install tools and foundry

```bash
yarn install
yarn install:foundry
```

### Build and test

```bash
yarn build
yarn test
```

### Deployment

A collection of the different SBT contract deployments and their addresses can be found in the [SBT deployments](https://github.com/dinaricrypto/sbt-deployments) repository.

Currently deployment scripts are only configured for testnet.

```bash
yarn deployall:testnet
```

For a new deployment, after the deploy script succeeds, copy the addresses and ABI to the SBT deployments repository under the new version directory.

### Staging setup

To deploy set of new asset tokens, set env vars

- `PRIVATE_KEY`
- `TRANSFER_RESTRICTOR`
- `SWAP_ISSUER`
- `DIRECT_ISSUER`

then run

```bash
yarn deploy:tokenlist:testnet
```

Security and Liability
----------------------
All contracts are WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
