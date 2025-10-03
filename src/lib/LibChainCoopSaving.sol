library LibChainCoopSaving {
    function generatePoolIndex(
        address _user,
        uint64 _time,
        uint64 _initialSavingAmount
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(_user, _time, _initialSavingAmount));
    }

    function calculateInterest(uint64 _principal)
        internal
        pure
        returns (uint64)
    {
        uint64 interest = (_principal * 3 * 100) / 10000;
        return interest;
    }
}
