pragma solidity 0.8.19;

import {DividendDistribution} from "../../src/dividend/DividendDistribution.sol";

// `DataHelper` is a utility contract for handling distribution data and interacting with the Dividenddistribution test contract.
contract DataHelper {
    // State variables for distribution addresses and corresponding amounts.
    address public distributionAddress0 = 0xB7E390864a90B7B923e9F9310c6f98aAFE43F707;
    address public distributionAddress1 = 0xEA674fdDe714fd979de3EdF0F56AA9716B898ec8;
    address public distributionAddress2 = 0xEA694FdDe714fD979dE3EdF0f56aA9716B898EC8;

    uint256 public distributionAmount0 = 10000000000000000000000000;
    uint256 public distributionAmount1 = 20000000000000000000000000;
    uint256 public distributionAmount2 = 20000000000000000000000000;

    // Function to generate an array of bytes32 hashes representing distribution data.
    function generateData(address _distribution) internal view returns (bytes32[] memory data) {
        // Get the distribution addresses and amounts.
        (address[] memory _user, uint256[] memory _amount) = getDistributionData();

        // Initialize the data array with the number of users.
        data = new bytes32[](_user.length);

        // Compute the hash for each user and corresponding amount, store it in the data array.
        for (uint256 i = 0; i < _user.length; i++) {
            data[i] = DividendDistribution(_distribution).hashLeaf(_user[i], _amount[i]);
        }
    }

    // Function to return arrays of distribution addresses and amounts.
    function getDistributionData() public view returns (address[] memory, uint256[] memory) {
        // Initialize an array of distribution addresses and set each element to the corresponding state variable.
        address[] memory _user = new address[](3);
        _user[0] = distributionAddress0;
        _user[1] = distributionAddress1;
        _user[2] = distributionAddress2;

        // Initialize an array of distribution amounts and set each element to the corresponding state variable.
        uint256[] memory _amount = new uint256[](3);
        _amount[0] = distributionAmount0;
        _amount[1] = distributionAmount1;
        _amount[2] = distributionAmount2;

        // Return the arrays of distribution addresses and amounts.
        return (_user, _amount);
    }
}
