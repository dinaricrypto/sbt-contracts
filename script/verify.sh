#!/bin/sh

cp .env.sandbox-plume-sepolia .env
source .env

# args
# forge verify-contract --chain-id 161221135 --verifier blockscout --watch --constructor-args $(cast abi-encode "constructor(address,bytes)" "0x638c2Fa8B02E8F294e8Af9d7F2248Ec1E085aa79" "0x000000000000000000000000702347e2b1be68444c1451922275b66aabdac5280000000000000000000000000fe4f28b0213201f333e9bf29fca76965a8c5fc80000000000000000000000003934aeee752235aee8139dbec4493639534eff2d000000000000000000000000aa5474bbb3aec03b81d1e280c821dbef60a7aabe") 0x94902a03f7E27c6f512B3E1E8cc7b1e1d2CCeE63 lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy
forge verify-contract --chain-id 161221135 --verifier blockscout --watch --constructor-args $(cast abi-encode "constructor(address)" "0x702347E2B1be68444C1451922275b66AABDaC528") 0x0F96bf4a333ab9f46B7bA9B873B99F6022798Aa5 src/dividend/DividendDistribution.sol:DividendDistribution
# no args
# forge verify-contract --chain-id 161221135 --verifier blockscout --watch 0x897627378772f7139Dda8fD16602019aA6d557F2 src/orders/OrderProcessor.sol:OrderProcessor
