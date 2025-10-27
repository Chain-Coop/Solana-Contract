// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IChainCoopSaving {
    enum LockingType {
        FLEXIBLE,
        LOCK,
        STRICTLOCK
    }

    struct SavingPool {
        address saver;
        address tokenToSaveWith;
        bytes32 reason;
        bytes32 poolIndex;
        uint64 startDate;
        uint64 duration;
        uint64 amountSaved;
        LockingType locktype;
        bool isGoalAccomplished;
        bool isStopped;
    }

    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    @mutableAccount(userContributedPools)
    @mutableAccount(userPoolBalance)
    @account(userTokenAccount)
    @account(vaultTokenAccount)
    @account(owner)
    function openSavingPool(
        address _tokenToSaveWith,
        uint64 _savedAmount,
        string memory _reason,
        LockingType _locktype,
        uint64 _duration
    ) external;

    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    @mutableAccount(userPoolBalance)
    @account(userTokenAccount)
    @account(vaultTokenAccount)
    function updateSaving(bytes32 _poolIndex, uint64 _amount) external;

    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    @mutableAccount(userContributedPools)
    @mutableAccount(userPoolBalance)
    @account(userTokenAccount)
    @account(vaultTokenAccount)
    @account(vaultAuthority)
    @account(feeTokenAccount)
    function withdraw(bytes32 _poolId) external;

    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    function stopSaving(bytes32 _poolId) external;

    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    function restartSaving(bytes32 _poolId) external;

    function getSavingPoolCount() external view returns (uint64);

    function getSavingPoolByIndex(bytes32 _index)
        external
        view
        returns (SavingPool memory);
}
