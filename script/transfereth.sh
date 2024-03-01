#!/bin/sh

cp .env.eth-sepolia .env
source .env

cast send -i 0xc644cc19d2A9388b71dd1dEde07cFFC73237Dca8 --value 0.5ether --rpc-url $RPC_URL