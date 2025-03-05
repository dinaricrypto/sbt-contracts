#!/bin/bash

# Required environment variables:
# RPC_URL            - RPC endpoint URL
# PRIVATE_KEY        - Deploy private key

forge script script/UpgradeBeaconWrappedDShare.s.sol -vvv --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --slow -vvv