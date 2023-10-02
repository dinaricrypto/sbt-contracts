#!/bin/sh

source .env

forge script script/TransferAll.s.sol:TransferAllScript --rpc-url $RPC_ARBITRUM --broadcast -vvvv
# cast send --rpc-url $RPC_ARBITRUM --private-key $SENDER_KEY --value $SEND_AMOUNT $TO
