// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20, IERC20, IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IOrderProcessor} from "../../src/orders/IOrderProcessor.sol";
import "prb-math/Common.sol" as PrbMath;
import {Nonces} from "openzeppelin-contracts/contracts/utils/Nonces.sol";
import {SelfPermit} from "../common/SelfPermit.sol";
import {IForwarder} from "./IForwarder.sol";

/// @notice Contract for paying gas fees for users and forwarding meta transactions to OrderProcessor contracts.
/// @author Dinari (https://github.com/dinaricrypto/issuer-contracts/blob/main/src/issuer/OrderProcessor.sol)
contract Forwarder is IForwarder, Ownable, Nonces, Multicall, SelfPermit, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20Permit;
    using SafeERC20 for IERC20;
    using Address for address;

    /// ------------------------------- Types -------------------------------

    error UserNotRelayer();
    error InvalidSigner();
    error InvalidAmount();
    error ExpiredRequest();
    error UnsupportedCall();
    error FeeTooHigh();
    error ForwarderNotApprovedByProcessor();
    error NotSupportedModule();
    error UnsupportedToken();
    error InvalidSplitRecipient();

    event RelayerSet(address indexed relayer, bool isRelayer);
    event SupportedModuleSet(address indexed module, bool isSupported);
    event FeeUpdated(uint256 feeBps);
    event CancellationGasCostUpdated(uint256 gas);
    event SellOrderGasCostUpdated(uint256 gas);
    event EthUsdOracleSet(address indexed oracle);
    event PaymentOracleSet(address indexed paymentToken, address indexed oracle);
    event UserOperationSponsored(
        address indexed user,
        address indexed paymentToken,
        uint256 actualTokenCharge,
        uint256 actualGasCost,
        uint256 actualTokenPrice
    );

    /// ------------------------------- Constants -------------------------------
    bytes private constant ORDER_TYPE = abi.encodePacked(
        "Order(address recipient,address assetToken,address paymentToken,bool sell,uint256 orderType,uint256 assetTokenQuantity,uint256 paymentTokenQuantity,uint256 price,uint256 tif,address splitRecipient,uint256 splitAmount)"
    );

    bytes32 private constant ORDER_TYPEHASH = keccak256(ORDER_TYPE);

    bytes private constant ORDER_FORWARDREQUEST_TYPE =
        abi.encodePacked("OrderForwardRequest(address user,address to,bytes32 orderHash,uint64 deadline,uint256 nonce)");

    bytes32 private constant ORDER_FORWARDREQUEST_TYPEHASH = keccak256(ORDER_FORWARDREQUEST_TYPE);

    bytes private constant CANCEL_FORWARDREQUEST_TYPE =
        abi.encodePacked("CancelForwardRequest(address user,address to,uint256 orderId,uint64 deadline,uint256 nonce)");

    bytes32 private constant CANCEL_FORWARDREQUEST_TYPEHASH = keccak256(CANCEL_FORWARDREQUEST_TYPE);

    /// ------------------------------- Storage -------------------------------

    /// @inheritdoc IForwarder
    uint16 public feeBps;

    /// @inheritdoc IForwarder
    uint256 public cancellationGasCost;

    uint256 public sellOrderGasCost;

    /// @notice The set of supported modules.
    mapping(address => bool) public isSupportedModule;

    /// @inheritdoc IForwarder
    mapping(address => bool) public isRelayer;

    /// @inheritdoc IForwarder
    mapping(uint256 => address) public orderSigner;

    address public ethUsdOracle;

    mapping(address => address) public paymentOracle;

    /// ------------------------------- Modifiers -------------------------------

    modifier onlyRelayer() {
        if (!isRelayer[msg.sender]) {
            revert UserNotRelayer();
        }
        _;
    }

    /// ------------------------------- Initialization -------------------------------

    /// @notice Constructs the Forwarder contract.
    /// @dev Initializes the domain separator used for EIP-712 compliant signature verification.
    constructor(address _ethUsdOracle, uint256 initialSellOrderGasCost) EIP712("Forwarder", "1") Ownable(msg.sender) {
        feeBps = 0;
        cancellationGasCost = 0;
        sellOrderGasCost = initialSellOrderGasCost;
        ethUsdOracle = _ethUsdOracle;
    }

    /// ------------------------------- Administration -------------------------------

    /// @notice Sets Relayer address state.
    /// @dev Only callable by the contract owner.
    function setRelayer(address newRelayer, bool _isRelayer) external onlyOwner {
        isRelayer[newRelayer] = _isRelayer;
        emit RelayerSet(newRelayer, _isRelayer);
    }

    /// @notice Sets the address of a supported module.
    /// @dev Only callable by the contract owner.
    function setSupportedModule(address module, bool isSupported) external onlyOwner {
        isSupportedModule[module] = isSupported;
        emit SupportedModuleSet(module, isSupported);
    }

    /// @notice Updates the fee rate.
    /// @dev Only callable by the contract owner.
    /// @param newFeeBps The new fee rate in basis points.
    function setFeeBps(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > 10000) revert FeeTooHigh();

        feeBps = newFeeBps;
        emit FeeUpdated(newFeeBps);
    }

    /// @notice Updates the cancellation gas cost estimate.
    /// @dev Only callable by the contract owner.
    /// @param newCancellationGasCost The new cancellation fee.
    function setCancellationGasCost(uint256 newCancellationGasCost) external onlyOwner {
        cancellationGasCost = newCancellationGasCost;
        emit CancellationGasCostUpdated(newCancellationGasCost);
    }

    function setSellOrderGasCost(uint256 newSellOrderGasCost) external onlyOwner {
        sellOrderGasCost = newSellOrderGasCost;
        emit SellOrderGasCostUpdated(newSellOrderGasCost);
    }

    /**
     * @dev add oracle for eth in usd
     * @param _ethUsdOracle chainlink oracle address
     */
    function setEthUsdOracle(address _ethUsdOracle) external onlyOwner {
        ethUsdOracle = _ethUsdOracle;
        emit EthUsdOracleSet(_ethUsdOracle);
    }

    /**
     * @dev add oracle for a payment token
     * @param paymentToken asset to add oracle
     * @param oracle chainlink oracle address
     */
    function setPaymentOracle(address paymentToken, address oracle) external onlyOwner {
        paymentOracle[paymentToken] = oracle;
        emit PaymentOracleSet(paymentToken, oracle);
    }

    /**
     * @notice Rescue ERC20 tokens locked up in this contract.
     * @param tokenContract ERC20 token contract address
     * @param to        Recipient address
     * @param amount    Amount to withdraw
     */
    function rescueERC20(IERC20 tokenContract, address to, uint256 amount) external onlyOwner {
        tokenContract.safeTransfer(to, amount);
    }

    /**
     * @notice Get the current oracle price for a payment token
     */
    function getPaymentPriceInWei(address paymentToken) public view returns (uint256) {
        if (paymentOracle[paymentToken] == address(0)) revert UnsupportedToken();
        return _getPaymentPriceInWei(paymentToken);
    }

    function _getPaymentPriceInWei(address paymentToken) internal view returns (uint256) {
        address _oracle = paymentOracle[paymentToken];
        // slither-disable-next-line unused-return
        (, int256 paymentPrice,,,) = AggregatorV3Interface(_oracle).latestRoundData();
        // slither-disable-next-line unused-return
        (, int256 ethUSDPrice,,,) = AggregatorV3Interface(ethUsdOracle).latestRoundData();
        // adjust values to align decimals
        uint8 paymentPriceDecimals = AggregatorV3Interface(_oracle).decimals();
        uint8 ethUSDPriceDecimals = AggregatorV3Interface(ethUsdOracle).decimals();
        if (paymentPriceDecimals > ethUSDPriceDecimals) {
            ethUSDPrice = ethUSDPrice * int256(10 ** (paymentPriceDecimals - ethUSDPriceDecimals));
        } else if (paymentPriceDecimals < ethUSDPriceDecimals) {
            paymentPrice = paymentPrice * int256(10 ** (ethUSDPriceDecimals - paymentPriceDecimals));
        }
        // compute payment price in wei
        uint256 paymentPriceInWei = PrbMath.mulDiv(uint256(paymentPrice), 1 ether, uint256(ethUSDPrice));
        return uint256(paymentPriceInWei);
    }

    /// ------------------------------- Forwarding -------------------------------

    /// @inheritdoc IForwarder
    function forwardRequestBuyOrder(OrderForwardRequest calldata metaTx)
        external
        onlyRelayer
        nonReentrant
        returns (uint256 orderId)
    {
        uint256 gasStart = gasleft();
        _validateOrderForwardRequest(metaTx);

        IOrderProcessor.Order memory order = metaTx.order;

        if (order.sell) revert UnsupportedCall();
        uint256 fees = IOrderProcessor(metaTx.to).estimateTotalFeesForOrder(
            metaTx.user, order.sell, order.paymentToken, order.paymentTokenQuantity
        );

        // Store order signer for processor
        uint256 nextOrderId = IOrderProcessor(metaTx.to).nextOrderId();
        orderSigner[nextOrderId] = metaTx.user;

        // slither-disable-next-line arbitrary-send-erc20
        IERC20(order.paymentToken).safeTransferFrom(metaTx.user, address(this), order.paymentTokenQuantity + fees);
        IERC20(order.paymentToken).safeIncreaseAllowance(metaTx.to, order.paymentTokenQuantity + fees);

        // execute request buy order
        orderId = IOrderProcessor(metaTx.to).requestOrder(order);

        // Check that reentrancy hasn't shifted order id
        assert(orderId == nextOrderId);

        uint256 assetPriceInWei = getPaymentPriceInWei(order.paymentToken);

        _handlePayment(metaTx.user, order.paymentToken, assetPriceInWei, gasStart);
    }

    /// @inheritdoc IForwarder
    function forwardRequestCancel(CancelForwardRequest calldata metaTx) external onlyRelayer nonReentrant {
        bytes32 typedDataHash = _hashTypedDataV4(cancelForwardRequestHash(metaTx));
        _validateForwardRequest(metaTx.user, metaTx.to, metaTx.deadline, metaTx.nonce, metaTx.signature, typedDataHash);

        if (orderSigner[metaTx.orderId] != metaTx.user) revert InvalidSigner();

        IOrderProcessor(metaTx.to).requestCancel(metaTx.orderId);
    }

    /// @inheritdoc IForwarder
    function forwardRequestSellOrder(OrderForwardRequest calldata metaTx)
        external
        onlyRelayer
        nonReentrant
        returns (uint256 orderId)
    {
        _validateOrderForwardRequest(metaTx);

        IOrderProcessor.Order memory order = metaTx.order;

        if (!order.sell) revert UnsupportedCall();
        if (order.splitRecipient != address(0)) revert InvalidSplitRecipient();

        // Configure order to take network fee from proceeds
        uint256 orderPaymentTokenPriceInWei = getPaymentPriceInWei(order.paymentToken);
        uint256 sellGasCostInToken =
            _tokenAmountForGas(sellOrderGasCost * tx.gasprice, order.paymentToken, orderPaymentTokenPriceInWei);
        uint256 fee = (sellGasCostInToken * feeBps) / 10000;
        order.splitAmount = sellGasCostInToken + fee;

        order.splitRecipient = msg.sender;

        // Store order signer for processor
        uint256 nextOrderId = IOrderProcessor(metaTx.to).nextOrderId();
        orderSigner[nextOrderId] = metaTx.user;

        // slither-disable-next-line arbitrary-send-erc20
        IERC20(order.assetToken).safeTransferFrom(metaTx.user, address(this), order.assetTokenQuantity);
        IERC20(order.assetToken).safeIncreaseAllowance(metaTx.to, order.assetTokenQuantity);

        // execute request sell order
        orderId = IOrderProcessor(metaTx.to).requestOrder(order);
        // Check that reentrancy hasn't shifted order id
        assert(orderId == nextOrderId);
    }

    /// @notice Validate OrderForwardRequest meta transaction.
    /// @param metaTx The meta transaction to validate.
    function _validateOrderForwardRequest(OrderForwardRequest calldata metaTx) internal {
        bytes32 typedDataHash = _hashTypedDataV4(orderForwardRequestHash(metaTx));
        _validateForwardRequest(metaTx.user, metaTx.to, metaTx.deadline, metaTx.nonce, metaTx.signature, typedDataHash);
        if (paymentOracle[metaTx.order.paymentToken] == address(0)) revert UnsupportedToken();
    }

    /// @notice Validates a meta transaction signature and nonce.
    /// @dev Reverts if the signature is invalid or the nonce has already been used.
    /// @param user The address of the user who signed the meta transaction.
    /// @param to The address of the target contract.
    /// @param deadline The deadline of the meta transaction.
    /// @param nonce The nonce of the meta transaction.
    /// @param signature The signature of the meta transaction.
    /// @param typedDataHash The EIP-712 typed data hash of the meta transaction.
    function _validateForwardRequest(
        address user,
        address to,
        uint256 deadline,
        uint256 nonce,
        bytes memory signature,
        bytes32 typedDataHash
    ) internal {
        if (deadline < block.timestamp) revert ExpiredRequest();
        if (!isSupportedModule[to]) revert NotSupportedModule();
        _useCheckedNonce(user, nonce);

        address signer = ECDSA.recover(typedDataHash, signature);
        if (signer != user) revert InvalidSigner();

        if (!IOrderProcessor(to).hasRole(IOrderProcessor(to).FORWARDER_ROLE(), address(this))) {
            revert ForwarderNotApprovedByProcessor();
        }
    }

    /// @inheritdoc IForwarder
    function orderForwardRequestHash(OrderForwardRequest calldata metaTx) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_FORWARDREQUEST_TYPEHASH,
                metaTx.user,
                metaTx.to,
                keccak256(
                    abi.encodePacked(
                        ORDER_TYPEHASH,
                        metaTx.order.recipient,
                        metaTx.order.assetToken,
                        metaTx.order.paymentToken,
                        metaTx.order.sell,
                        metaTx.order.orderType,
                        metaTx.order.assetTokenQuantity,
                        metaTx.order.paymentTokenQuantity,
                        metaTx.order.price,
                        metaTx.order.tif,
                        metaTx.order.splitRecipient,
                        metaTx.order.splitAmount
                    )
                ),
                metaTx.deadline,
                metaTx.nonce
            )
        );
    }

    /// @inheritdoc IForwarder
    function cancelForwardRequestHash(CancelForwardRequest calldata metaTx) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CANCEL_FORWARDREQUEST_TYPEHASH, metaTx.user, metaTx.to, metaTx.orderId, metaTx.deadline, metaTx.nonce
            )
        );
    }

    function _tokenAmountForGas(uint256 gasCostInWei, address token, uint256 paymentTokenPrice)
        internal
        view
        returns (uint256)
    {
        // Apply payment token price to calculate payment amount
        // Assumes payment token price includes token decimals
        uint256 paymentAmount = 0;
        try IERC20Metadata(token).decimals() returns (uint8 value) {
            paymentAmount = gasCostInWei * 10 ** value / paymentTokenPrice;
        } catch {
            paymentAmount = gasCostInWei / paymentTokenPrice;
        }
        return paymentAmount;
    }

    /**
     * @dev Handles the payment of transaction fees in the form of tokens. Calculates the
     *      gas used for the transaction and transfers the equivalent amount in tokens from
     *      the user to the relayer.
     *
     * @param user The address of the user who is paying the transaction fees.
     * @param paymentToken The address of the ERC20 token used for payment.
     * @param paymentTokenPrice The price of the payment token in terms of wei.
     * @param gasStart The amount of gas at the start of the transaction.
     */
    function _handlePayment(address user, address paymentToken, uint256 paymentTokenPrice, uint256 gasStart) internal {
        uint256 gasUsed = gasStart - gasleft();
        uint256 totalGasCostInWei = (gasUsed + cancellationGasCost) * tx.gasprice;
        uint256 paymentAmount = _tokenAmountForGas(totalGasCostInWei, paymentToken, paymentTokenPrice);

        // Apply forwarder fee
        // slither-disable-next-line divide-before-multiply
        uint256 fee = (paymentAmount * feeBps) / 10000;
        uint256 actualTokenCharge = paymentAmount + fee;

        emit UserOperationSponsored(user, paymentToken, actualTokenCharge, totalGasCostInWei, paymentTokenPrice);
        // Transfer the payment for gas fees
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(paymentToken).safeTransferFrom(user, msg.sender, actualTokenCharge);
    }

    // slither-disable-next-line naming-convention
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
