// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20, IERC20, IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IOrderProcessor} from "../../src/orders/IOrderProcessor.sol";
import {Nonces} from "openzeppelin-contracts/contracts/utils/Nonces.sol";
import {SelfPermit} from "../common/SelfPermit.sol";
import {IForwarder} from "./IForwarder.sol";

/// @notice Contract for paying gas fees for users and forwarding meta transactions to OrderProcessor contracts.
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/forwarder/Forwarder.sol)
abstract contract Forwarder is IForwarder, Ownable, Nonces, Multicall, SelfPermit, ReentrancyGuard, EIP712 {
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
    event UserOperationSponsored(
        address indexed user,
        address indexed paymentToken,
        uint256 actualTokenCharge,
        uint256 actualGasCost,
        uint256 actualTokenPrice
    );

    /// ------------------------------- Constants -------------------------------

    bytes private constant FORWARDREQUEST_TYPE =
        abi.encodePacked("ForwardRequest(address user,address to,bytes data,uint64 deadline,uint256 nonce)");
    bytes32 private constant FORWARDREQUEST_TYPEHASH = keccak256(FORWARDREQUEST_TYPE);

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
    constructor(uint256 initialSellOrderGasCost) EIP712("Forwarder", "1") Ownable(msg.sender) {
        feeBps = 0;
        cancellationGasCost = 0;
        sellOrderGasCost = initialSellOrderGasCost;
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
        if (!isSupportedToken(paymentToken)) revert UnsupportedToken();
        return _getPaymentPriceInWei(paymentToken);
    }

    /// ------------------------------- Forwarding -------------------------------

    /// @inheritdoc IForwarder
    function forwardRequestBuyOrder(ForwardRequest calldata metaTx)
        external
        onlyRelayer
        nonReentrant
        returns (bytes memory result)
    {
        uint256 gasStart = gasleft();
        _validateForwardRequest(metaTx);

        _validateFunctionSelector(metaTx.data, IOrderProcessor.requestOrder.selector);

        (IOrderProcessor.Order memory order) = abi.decode(metaTx.data[4:], (IOrderProcessor.Order));
        if (order.sell) revert UnsupportedCall();
        uint256 fees = IOrderProcessor(metaTx.to).estimateTotalFeesForOrder(
            metaTx.user, order.sell, order.paymentToken, order.paymentTokenQuantity
        );

        // Store order signer for processor
        uint256 orderId = IOrderProcessor(metaTx.to).nextOrderId();
        orderSigner[orderId] = metaTx.user;

        // slither-disable-next-line arbitrary-send-erc20
        IERC20(order.paymentToken).safeTransferFrom(metaTx.user, address(this), order.paymentTokenQuantity + fees);
        IERC20(order.paymentToken).safeIncreaseAllowance(metaTx.to, order.paymentTokenQuantity + fees);

        // execute low level call to issuer
        result = metaTx.to.functionCall(metaTx.data);

        // Check that reentrancy hasn't shifted order id
        assert(abi.decode(result, (uint256)) == orderId);

        uint256 assetPriceInWei = getPaymentPriceInWei(order.paymentToken);

        _handlePayment(metaTx.user, order.paymentToken, assetPriceInWei, gasStart);
    }

    /// @inheritdoc IForwarder
    function forwardRequestCancel(ForwardRequest calldata metaTx)
        external
        onlyRelayer
        nonReentrant
        returns (bytes memory result)
    {
        _validateForwardRequest(metaTx);

        _validateFunctionSelector(metaTx.data, IOrderProcessor.requestCancel.selector);

        uint256 orderId = abi.decode(metaTx.data[4:], (uint256));
        if (orderSigner[orderId] != metaTx.user) revert InvalidSigner();

        result = metaTx.to.functionCall(metaTx.data);
    }

    /// @inheritdoc IForwarder
    function forwardRequestSellOrder(ForwardRequest calldata metaTx)
        external
        onlyRelayer
        nonReentrant
        returns (bytes memory result)
    {
        _validateForwardRequest(metaTx);

        _validateFunctionSelector(metaTx.data, IOrderProcessor.requestOrder.selector);

        (IOrderProcessor.Order memory order) = abi.decode(metaTx.data[4:], (IOrderProcessor.Order));

        if (!order.sell) revert UnsupportedCall();
        if (order.splitRecipient != address(0)) revert InvalidSplitRecipient();

        // Configure order to take network fee from proceeds
        uint256 orderPaymentTokenPriceInWei = getPaymentPriceInWei(order.paymentToken);
        uint256 sellGasCostInToken =
            _tokenAmountForGas(sellOrderGasCost * tx.gasprice, order.paymentToken, orderPaymentTokenPriceInWei);
        uint256 fee = (sellGasCostInToken * feeBps) / 10000;
        order.splitAmount = sellGasCostInToken + fee;

        order.splitRecipient = msg.sender;

        bytes memory data = abi.encodeWithSelector(IOrderProcessor.requestOrder.selector, order);

        // Store order signer for processor
        uint256 orderId = IOrderProcessor(metaTx.to).nextOrderId();
        orderSigner[orderId] = metaTx.user;

        // slither-disable-next-line arbitrary-send-erc20
        IERC20(order.assetToken).safeTransferFrom(metaTx.user, address(this), order.assetTokenQuantity);
        IERC20(order.assetToken).safeIncreaseAllowance(metaTx.to, order.assetTokenQuantity);

        // execute low level call to issuer
        result = metaTx.to.functionCall(data);
        // Check that reentrancy hasn't shifted order id
        assert(abi.decode(result, (uint256)) == orderId);
    }

    /**
     * @dev Validates the function selector of the encoded function call data.
     * @param data The encoded function call data.
     * @param functionSelector The expected function selector.
     */
    function _validateFunctionSelector(bytes calldata data, bytes4 functionSelector) internal pure {
        bytes4 selector = bytes4(data[:4]);
        if (selector != functionSelector) revert UnsupportedCall();
    }

    /**
     * @dev Validates the forward request by checking the oracle price, target address, deadline,
     *      verifying the price attestation, checking the nonce, and ensuring that the signer of the request is valid.
     * @param metaTx The meta transaction containing the user address, target contract, encoded function call data,
     *      deadline, nonce, payment token oracle price, and the signature components (v, r, s).
     */
    function _validateForwardRequest(ForwardRequest calldata metaTx) internal {
        if (metaTx.deadline < block.timestamp) revert ExpiredRequest();
        if (!isSupportedModule[metaTx.to]) revert NotSupportedModule();
        // slither-disable-next-line unused-return
        _useCheckedNonce(metaTx.user, metaTx.nonce);

        if (bytes4(metaTx.data[:4]) == IOrderProcessor.requestOrder.selector) {
            (IOrderProcessor.Order memory order) = abi.decode(metaTx.data[4:], (IOrderProcessor.Order));
            if (!isSupportedToken(order.paymentToken)) revert UnsupportedToken();
        }

        bytes32 typedDataHash = _hashTypedDataV4(forwardRequestHash(metaTx));

        address signer = ECDSA.recover(typedDataHash, metaTx.signature);
        if (signer != metaTx.user) revert InvalidSigner();

        // Verify that orderprocessor has approved this as forwarder
        if (!IOrderProcessor(metaTx.to).hasRole(IOrderProcessor(metaTx.to).FORWARDER_ROLE(), address(this))) {
            revert ForwarderNotApprovedByProcessor();
        }
    }

    /// @inheritdoc IForwarder
    function forwardRequestHash(ForwardRequest calldata metaTx) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                FORWARDREQUEST_TYPEHASH, metaTx.user, metaTx.to, keccak256(metaTx.data), metaTx.deadline, metaTx.nonce
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

    /// ------------------------------- Oracle Usage -------------------------------

    function isSupportedToken(address token) public view virtual returns (bool);

    function _getPaymentPriceInWei(address paymentToken) internal view virtual returns (uint256);
}
