// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solady/auth/Ownable.sol";
import "solady/utils/ECDSA.sol";
import "solady/utils/EIP712.sol";
import "./IBridgedERC20.sol";

/// @notice ERC20 with minter and blacklist.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/DinariERC20.sol)
contract Bridge is Ownable, EIP712 {
    // This contract handles the submission and fulfillment of orders
    // forwarder/gsn support?
    // TODO: one bridge per token, or per network?

    struct MarketQuote {
        uint32 blockNumber; // change to time if needed
        uint224 value;
    }

    struct MarketOrderInfo {
        uint256 amount;
        uint256 maxSlippage;
    }

    error WrongPriceOracle();

    event PriceOracleSet(address indexed oracle, bool state);

    bytes32 public constant MARKETQUOTE_TYPE_HASH =
        keccak256("MarketQuote(uint32 blockNumber, uint224 value)");

    IBridgedERC20 public token;

    /// @dev How long a quote is valid in blocks
    uint32 public quoteDuration;

    uint256 public defaultMaxSlippage;

    /// @dev trusted oracles for this issuer
    mapping(address => bool) public priceOracle;

    /// @dev unfulfilled orders
    // TODO: make collection efficient
    // TODO: need beneficiary account and price info
    // TODO: generalize order queuing across order types? support limit in future?
    MarketOrderInfo[] private _orders;

    // per block quote (price, time)
    // - can this be a pass-through calldata quote signed by our oracle? then we can serve from out API and save gas
    // - check how quotes currently work in bridges etc.
    // max slippage
    // amount
    constructor(
        IBridgedERC20 token_,
        uint32 quoteDuration_,
        uint256 defaultMaxSlippage_
    ) {
        token = token_;
        quoteDuration = quoteDuration_;
        defaultMaxSlippage = defaultMaxSlippage_;
    }

    /// @dev never call this on chain
    function getOrders() external view returns (MarketOrderInfo[] memory) {
        return _orders;
    }

    function hashMarketQuote(
        MarketQuote memory quote
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    MARKETQUOTE_TYPE_HASH,
                    quote.blockNumber,
                    quote.value
                )
            );
    }

    function setPriceOracle(address oracle, bool state) external onlyOwner {
        priceOracle[oracle] = state;
        emit PriceOracleSet(oracle, state);
    }

    function submitPurchase(
        MarketOrderInfo calldata marketOrder,
        MarketQuote calldata quote,
        bytes calldata signedQuote
    ) external {
        // TODO: should we allow beneficiary != msg.sender?
        address oracleAddress = ECDSA.recoverCalldata(
            _hashTypedData(hashMarketQuote(quote)),
            signedQuote
        );
        if (!priceOracle[oracleAddress]) revert WrongPriceOracle();
    }

    function submitRedemption(
        MarketOrderInfo calldata marketOrder,
        MarketQuote calldata quote,
        bytes calldata signedQuote
    ) external {
        address oracleAddress = ECDSA.recoverCalldata(
            _hashTypedData(hashMarketQuote(quote)),
            signedQuote
        );
        if (!priceOracle[oracleAddress]) revert WrongPriceOracle();
    }

    function _domainNameAndVersion()
        internal
        pure
        virtual
        override
        returns (string memory name, string memory version)
    {
        return ("Bridge", "1");
    }
}
