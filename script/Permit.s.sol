// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SigUtils} from "../test/utils/SigUtils.sol";

interface IVersion {
    function version() external view returns (string memory);
}

contract Permit is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address usdb = vm.envAddress("USDB");

        bytes32 domainSeparator;
        {
            string memory name = ERC20(usdb).name();
            // string memory version = "1.0.0";
            string memory version = IVersion(usdb).version();
            console.log("USDB version: %s", version);
            uint256 chainId = block.chainid;
            address verifyingContract = usdb;

            // Construct domain separator
            domainSeparator = keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(name)),
                    keccak256(bytes(version)),
                    chainId,
                    verifyingContract
                )
            );
            bytes32 currentDomainSeparator = IERC20Permit(usdb).DOMAIN_SEPARATOR();
            if (domainSeparator != currentDomainSeparator) {
                console.log("Domain separator mismatch");
                console.logBytes32(domainSeparator);
                console.logBytes32(currentDomainSeparator);
            } else {
                console.log("Domain separator matches");
            }
        }

        SigUtils sigUtils = new SigUtils(domainSeparator);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: deployer,
            spender: usdb,
            value: 10,
            nonce: IERC20Permit(usdb).nonces(deployer),
            deadline: block.timestamp + 30 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest);

        vm.startBroadcast(deployerPrivateKey);

        IERC20Permit(usdb).permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.stopBroadcast();
    }
}
