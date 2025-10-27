// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

library LibChainCoopSaving {
    function generatePoolIndex(address user, uint64 index) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, index));
    }

    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function calculateInterest(uint64 _principal) internal pure returns (uint64) {
        uint64 interest = (_principal * 3) / 100; // 3% interest
        return interest;
    }
}
