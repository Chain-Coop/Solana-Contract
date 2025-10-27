// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

library LibChainCoopSaving {
    // Generate unique pool index
    function generatePoolIndex(address user, uint64 index) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, index));
    }

    // Helper function to convert string to bytes32 (no inline assembly)
    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        if (temp.length == 0) {
            return 0x0;
        }
        // Take the first 32 bytes of the string
        if (temp.length > 32) {
            assembly {
                mstore(add(result, 0), mload(add(source, 32)))
            }
        } else {
            bytes32 tempBytes;
            for (uint256 i = 0; i < temp.length; i++) {
                tempBytes |= bytes32(uint8(temp[i])) >> (i * 8);
            }
            result = tempBytes;
        }
    }

    // Calculate 3% interest safely
    function calculateInterest(uint64 _principal) internal pure returns (uint64) {
        uint64 interest = (_principal * 3) / 100; // 3%
        return interest;
    }
}
