// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

interface ITokenManagerType {
    enum TokenManagerType {
        MINT_BURN,
        MINT_BURN_FROM,
        LOCK_UNLOCK,
        LOCK_UNLOCK_FEE
    }
}
