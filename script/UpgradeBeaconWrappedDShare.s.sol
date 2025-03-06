// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {WrappedDShare} from "../src/WrappedDShare.sol";
import {console2} from "forge-std/console2.sol";
import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

contract UpgradeWrappedDShareScript is Script {
    UpgradeableBeacon beacon = UpgradeableBeacon(0xad20601C7a3212c7BbF2ACdFEDBAD99d803bC7F5);
    IMulticall3 multicall = IMulticall3(0xcA11bde05977b3631167028862bE2a173976CA11);

    // Array of existing WrappedDShare addresses
    address[] wrappedDShareAddresses = [
        0xA6B1bC15a4289899309BA0439D4037084fa2d457,
        0xee0d00A79aFeB121880f5Bf2273DEbbF7f60EA02,
        0x5b4C01175e9809A7f352197E953F8D9A2aE2d12F,
        0xF82F6801FA5Ab466C8820F08C9C7Adf893AC8d6F,
        0xbAc491F9cdD0c1A05c18492232827ca009B64945,
        0xbdA5a1e73410730325CEA424F3DbD8A2eCc69514,
        0x9Ea41FDFb479A0Eb2b43EF4cB2248E13436f5e07,
        0xF8C652054a60224E2d9c774Bfd118f6a27d5bCEf,
        0x3c5bEbe8998137E390b0cb791B42bF538353451b,
        0xb5d09652f40630b287bC067270C79E1402f28599,
        0xD767EE961A00921D69721c0F9999546d5235e6f9,
        0xADf3Cd8759Bd8bA9106342d1494b4Fb4b3720923,
        0x42112C40C4d4f5be3b64B113A55D307a30716964,
        0x407274ABb9241Da0A1889c1b8Ec65359dd9d316d,
        0xef8c9C08EE50bD31377a309b879FC9AFD1302c83,
        0xCc3Dc0Ac609E6b78bb8CD7a3b27C2C7688272F8a,
        0x6bb71b2bdd892c5EfB960a76EDeC03b1F04551F4,
        0x0C39B0146F774FE4aEBC62E1dDDE7AA03A3534f1,
        0xe744C9Ca2A5a7651DD59B0ff897E5B00AbF605e3,
        0xF3D26Aa97ad896B764767cC6d9c1Be2637C34287,
        0x57D7cB764bF041A7b1bcE7B01E097294b6a891b0,
        0x4C4C794adeC19665f2Ac4d3D7abA7e761d24920A,
        0x98Cd8262B129f3bcdd50B633D193db134bEE28C5,
        0x5bF7d0F8C178BB5b678Bf6bC20a2E499a85cFD4B,
        0x2f3990A7A0B454bb149Df647c9Eeb8c8DaFE1E82,
        0xedebC5ba1B480AF3C938B1873BDdcACad35D3828,
        0x7e8b163DAf001b50aeA7f0799FEA7ebe74428876,
        0x4E63c472B5F490FDDb50D915FC5A0851f6421cfF,
        0x0f11c59A15ad1e033d7DDABA82cABE0CBCD314Ab,
        0xc9faF488f9631668895117Ef9649C3f3f1869C86,
        0x8821AbD917364C39811E4d3e9Ca5a6D75769395a,
        0xeb4DefF87a9711610a1EC4D15855245b11CeaC02,
        0xe1624E776909DF49429D87429De9E01AdD1640A9,
        0x32c8fB151C8202Ee59bCDD6D817707932E7C237E,
        0xFe0FeD39Ce30127701b828f74C65074bD2c31e9c,
        0x0D96C06c2b44fF34c139aaB3e47F51880a83E3D7,
        0xdB9ACb028D3c30f6Daf40ab4D0bDbFb4eaD7F8aD,
        0x2A1Fe6b14B3815b0F630cAb269A0984F234dcb5D,
        0xE2a3ecD5Fbd130a0998a280f7CC2B22C19cB0207,
        0x2F71B3804a74A013d00065225752dBA9aD061e51,
        0x43333771E8d5FD74E5491d10aeAc2BFdC23D19C8,
        0xd47990dfEAe1a7faDa2FdbcAF80df2CBa5cEf773,
        0xfeb0576B12316368dFd32eEce3eB86841625C55e,
        0x00Ad8047a19a1720f7F6bd9Ae98bA06f844253FF,
        0xA3811ddC4ECfAb575E9066f285c95863Ba932e06,
        0x83643FE57f1615d27cb6B8e59a37758B57fc8de9,
        0x862198F6e65d50c9a7090fBCA090A21e92B300d4,
        0x20B4ed91154ba9A3173FA5a598136bD5F30DFfb4,
        0x6AAC4227777d0D14C06C00964d31c3a54f2f7480,
        0x6E3849390e66a5e88a155A2DBd9F372cfda24f6F,
        0x6aA6a6AeaF8EEF38b178d3cDB892cbC57ee491Ca,
        0x9deda619B8E208a2F2894502da3950b923521360,
        0x18ebe5ab29478e5696cca4eF1929712b92A8E043,
        0xBCd0a1dd73A5452A4d2A27fF8f10067d04bC80b1,
        0x226490278C5739c04576f00F68415bb83ea2adD7,
        0xB2f838eC649Ff932D6B2Fc5da60E15C47a0dD4ea,
        0x8F0d3676B44d9a88872c9247e8967781CEEf22d2,
        0x8F9AE11C768ad0B557ACEBDD6d75fa5a7Ea34e06,
        0xceBB37Dd94C58AA029d677113ad6800dbF8A4BE6,
        0xc18a52988F805f7D875f10906dc8B91522d68039,
        0xF1e82bf4e1Ce55b691b2916F3dfC5932B541dF21,
        0x107E6F86D1C8C4cC341bC2bA158630FaBd632aEE,
        0xD7813488d46E840E4dC2A721965E3059D6F3AB92,
        0x85B5dCE43632cF788e2c58ED1a28Bd0eaf0Fe8cC,
        0x64E9B9b1C18E6F2D91ab8F97925F985CeC7d5358,
        0x71840ffBCbcE94143369cE915783fba83394a6a4,
        0xCD7fF7fe1Daf8287f2C055C0a452d54c41E07A85,
        0x053e5ff04C7157fb4D7CDd5D322fC926e260662E,
        0x7F8E2a391409DB3c6F8Fe7554Fd983A202992783,
        0x3ebBD59E28922371a0a34621dAB67Ed0D8b4c9d1,
        0x105AC1Fdfff87Bcd3a8624c5fD10a4e8b7184278,
        0xD3c5FEFDB9a7F26E57F4Cd79496b837714Ce3bE0,
        0x4c2d5D49DFe80d464F127AaD7192889B12aC9565,
        0x006a0f7B722F4f5893d3473A86fED3FdA4b19b17,
        0xd569625C7fb037F7dC6BA31E5c5bBE3eB28a523B,
        0xC576AACB6E13955712f08D26930062991DE3c45D,
        0x9db67d2AcF8Dc4e1A1e2291A9fdb254a17c8c104,
        0x2a086C686cbCe72D1EF4B068Ff40fa5aC4B7d280,
        0xc5e2A02bd76A518552275479B64a63568482B9fA,
        0x3ca7ea0D7759c907E2aF0Af47B58BFe0D8BF9E61,
        0x6d090e698e73F759E05AB4499d11199f6EA39f20,
        0xa0718F7b3D0d393761D4bA589c33562988CaD786,
        0x4c972673CA84C6e917D6c654653904626dcCA51E,
        0x9E1565eaB3398894Ddb0508771EbE133d23CDe50,
        0x68DC395F03915Ba5cFA377E0529bD0719b765EFB,
        0x3c8B063f7b147b7065a816D114beC771C8Dd82a5,
        0x7EE32000524aaFE9B0b8c0C751bc95487E9cAf01,
        0x3cd47D9D04f9Bb7eEa4FfEbC576f61EC445f45ea,
        0xaCbf830c129F4e345071a494c6f4db07ee4e252F,
        0x6725E09469101B37527B1484F401cd3f4B8F67CB,
        0x0273130964C6ccbE2de90E0B2824863782a8e98D,
        0x1304B173364Dd4aa059aB6E5be4b817087d10283,
        0xF27c6608355DE4Ae2867649530558EB21B23F2c5,
        0xd1B6407f75127D49405cb130CEF9313428FA659d,
        0x10186D591f70507EA6479a38148164380531C0Ec,
        0x2898Dee134D3Faf3170e6E70F04F9752b18E4E07,
        0xFB33654d2B4b25070Fa47fFf2bBb3af9EBb9a75F,
        0x88635b68484007Fe424C0AE19bd11BeBF3071A29,
        0xa2f294F0F19EBF373f2E8269f5dC25282ec2e807,
        0x89102A30b156Ce4108db7Ef86EEc27810fdeF64e,
        0x929e2a99DEAcD604e6D776225D8a0c6f71291Fe9
    ];

    function run() external {
        address owner = beacon.owner();
        console2.log("Beacon Owner:", owner);

        vm.startBroadcast(owner);
        console2.log("Current Beacon Implementation:", beacon.implementation());

        // Deploy new implementation with AccessControl
        WrappedDShare newImpl = new WrappedDShare();
        console2.log("New Implementation Deployed At:", address(newImpl));

        // Upgrade beacon
        beacon.upgradeTo(address(newImpl));
        console2.log("Beacon Upgraded To:", beacon.implementation());

        // Prepare Multicall3 calls
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](wrappedDShareAddresses.length);

        // Add calls for initializeV2
        for (uint256 i = 0; i < wrappedDShareAddresses.length; i++) {
            calls[i] = IMulticall3.Call3({
                target: wrappedDShareAddresses[i],
                allowFailure: false,
                callData: abi.encodeWithSelector(WrappedDShare.initializeV2.selector)
            });
        }

        // Execute Multicall3
        console2.log("Executing Multicall3...");
        IMulticall3.Result[] memory r = multicall.aggregate3(calls);

        // Sanity check results
        for (uint256 i = 0; i < wrappedDShareAddresses.length; i++) {
            WrappedDShare wc = WrappedDShare(wrappedDShareAddresses[i]);
            console2.log("Does owner have role?", wc.hasRole(wc.DEFAULT_ADMIN_ROLE(), owner));
        }

        vm.stopBroadcast();
    }
}
