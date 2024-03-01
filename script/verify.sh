#!/bin/sh

cp .env.blast-sepolia .env
source .env

# args
# forge verify-contract --chain-id 168587773 --watch --constructor-args $(cast abi-encode "constructor(address,bytes)" "0x51E5b891A9972D85cC1EadE4cAC9E5fB50B5477a" "0xc0c53b8b0000000000000000000000004181803232280371e02a875f51515be57b2152310000000000000000000000004181803232280371e02a875f51515be57b21523100000000000000000000000090a0cf0d7ec1b6b963a011dc085346ff0f03643d") 0xC8E1D95300b1E6bFD401400B3b8E7a5bFD8Aeb02 lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy
# forge verify-contract --chain-id 42161 --watch --constructor-args $(cast abi-encode "constructor(address)" "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612") 0x14D3498e4816c2B8F017677356dca051e28a33c8 src/forwarder/Forwarder.sol:Forwarder
# no args
forge verify-contract --chain-id 168587773 --watch 0x4502C8376F7f28B17594Bff38d19631f7Cddec15 src/orders/BuyUnlockedProcessor.sol:BuyUnlockedProcessor
