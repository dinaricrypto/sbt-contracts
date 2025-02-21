#!/bin/sh
# RPC_URL - mandatory
# VERIFY_URL - optional
# PRIVATE_KEY - mandatory
# ETHERSCAN_API_KEY - optional

# export VERSION="" # 1.0.0 - mandatory
# export ENVIRONMENT="" #[staging, production] - mandatory


CONTRACTS=("usdplus" "transfer_restrictor" "usdplus_minter" "usdplus_redeemer" "ccip_waypoint")

for i in "${CONTRACTS[@]}"; do
    echo "Deploying $i"
    export CONTRACT=$i
    
    FORGE_CMD="forge script script/Release.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvv"
    
    if [ ! -z "$ETHERSCAN_API_KEY" ] || [ ! -z "$VERIFIER_URL" ]; then
        FORGE_CMD="$FORGE_CMD --verify"
    fi
    
    eval $FORGE_CMD || echo "Failed to deploy $i, continuing..."
done

echo "Deployment process completed."