// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./lib/LibChainCoopSaving.sol";
import "./lib/spl_token.sol";
import "./ChainCoopManagement.sol";
import "./interface/IChainCoopSaving.sol";

@program_id("HSgbc9ZehSwuPf82se5KZ8UT3zHfbMQpFARFa2456YU7")
contract ChainCoopSaving is IChainCoopSaving {
    using LibChainCoopSaving for *;

    // Storage
    mapping(bytes32 => IChainCoopSaving.SavingPool) public poolSavingPool;
    // Avoid dynamic array push/pop issues on Windows/Solang by using an indexed mapping
    mapping(address => mapping(uint64 => bytes32)) private userPoolsByIndex;
    mapping(address => uint64) private userPoolCount; // number of pools per user

    mapping(address => mapping(bytes32 => uint64)) public userPoolBalance;

    uint64 private totalPools;

    // Reference to ChainCoopManagement to check allowed tokens / fees (optional)
    address public chainCoopManagementAddress;

    // Owner (program admin)
    address public owner;

    // Events
    event PoolOpened(address indexed saver, bytes32 poolId, uint64 amount, uint64 poolIndex);
    event PoolUpdated(address indexed saver, bytes32 poolId, uint64 newAmount);
    event Withdraw(address indexed saver, address token, uint64 amount, bytes32 poolId);
    event PoolClosed(address indexed saver, bytes32 poolId);
    event PoolStopped(address indexed saver, bytes32 poolId);
    event PoolRestarted(address indexed saver, bytes32 poolId);

    // -------------------------
    // Initialization (Solana-friendly)
    // -------------------------
    // Call this once after deployment. It replaces the constructor pattern.
    @signer(ownerAccount)
    function initialize(address _chainCoopManagement) external {
        require(owner == address(0), "Already initialized");
        require(tx.accounts.ownerAccount.key != address(0), "Invalid owner");
        owner = tx.accounts.ownerAccount.key;
        chainCoopManagementAddress = _chainCoopManagement;
        totalPools = 0;
    }

    /* -------------------------
       Helper / Internal
       ------------------------- */

    function _isTokenAllowed(address token) internal view returns (bool) {
        if (chainCoopManagementAddress == address(0)) {
            return true; // if management not set, accept
        }
        ChainCoopManagement mgmt = ChainCoopManagement(chainCoopManagementAddress);
        return mgmt.isTokenAllowed(token);
    }

    function _makePoolId(address saver, uint64 index, uint64 startDate) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(saver, index, startDate));
    }

    /* -------------------------
       Open a new saving pool
       ------------------------- */
    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    @mutableAccount(userContributedPools)
    @mutableAccount(userPoolBalance)
    @account(userTokenAccount)
    @account(vaultTokenAccount)
    @account(owner)
    function openSavingPool(
        address _tokenTosaveWith,
        uint64 _savedAmount,
        string memory /* _reason (kept for external API compatibility) */,
        LockingType _locktype,
        uint64 _duration
    ) external override {
        address signer = tx.accounts.userAccount.key;
        require(signer != address(0), "Invalid signer");
        require(_savedAmount > 0, "Amount must be > 0");
        require(_isTokenAllowed(_tokenTosaveWith), "Token not allowed");

        // create an index for this user's pool
        uint64 userIndex = userPoolCount[signer];
        uint64 startDate = uint64(block.timestamp);

        bytes32 poolId = _makePoolId(signer, userIndex, startDate);

        IChainCoopSaving.SavingPool storage pool = poolSavingPool[poolId];

        pool.saver = signer;
        pool.tokenToSaveWith = _tokenTosaveWith;
        // Reason stored off-chain or as bytes32: left empty to avoid dynamic string storage issues
        pool.Reason = bytes32(0);
        pool.poolIndex = poolId;
        pool.startDate = startDate;
        pool.Duration = _duration;
        pool.amountSaved = _savedAmount;
        pool.locktype = _locktype;
        pool.isGoalAccomplished = false;
        pool.isStoped = false;

        // Store mapping index
        userPoolsByIndex[signer][userIndex] = poolId;
        userPoolCount[signer] = userIndex + 1;

        // Update totals
        totalPools += 1;

        // Track user's balance for this pool
        userPoolBalance[signer][poolId] = _savedAmount;

        // Transfer tokens from user to vault (assumes user already approved or associated)
        SplToken.transfer(
            tx.accounts.userTokenAccount.key,
            tx.accounts.vaultTokenAccount.key,
            tx.accounts.userAccount.key, // signer is authority on user's token account
            _savedAmount
        );

        emit PoolOpened(signer, poolId, _savedAmount, userIndex);
    }

    /* -------------------------
       Update an existing pool
       ------------------------- */
    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    @mutableAccount(userPoolBalance)
    @account(userTokenAccount)
    @account(vaultTokenAccount)
    function updateSaving(bytes32 _poolIndex, uint64 _amount) external override {
        address signer = tx.accounts.userAccount.key;
        IChainCoopSaving.SavingPool storage pool = poolSavingPool[_poolIndex];

        require(pool.saver == signer, "Not the pool owner");
        require(!pool.isStoped, "Pool is stopped");
        require(_amount > 0, "Amount must be > 0");

        // increase pool and user balance
        pool.amountSaved += _amount;
        userPoolBalance[signer][_poolIndex] += _amount;

        // Transfer tokens from user to vault
        SplToken.transfer(
            tx.accounts.userTokenAccount.key,
            tx.accounts.vaultTokenAccount.key,
            tx.accounts.userAccount.key,
            _amount
        );

        emit PoolUpdated(signer, _poolIndex, pool.amountSaved);
    }

    /* -------------------------
       Withdraw
       ------------------------- */
    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    @mutableAccount(userContributedPools)
    @mutableAccount(userPoolBalance)
    @account(userTokenAccount)
    @account(vaultTokenAccount)
    @account(vaultAuthority)
    @account(feeTokenAccount)
    function withdraw(bytes32 _poolId) external override {
        address signer = tx.accounts.userAccount.key;
        IChainCoopSaving.SavingPool storage pool = poolSavingPool[_poolId];

        require(pool.saver != address(0), "Pool does not exist");
        require(pool.saver == signer, "Not pool owner");
        require(!pool.isStoped, "Pool is stopped");
        require(pool.amountSaved > 0, "No funds to withdraw");

        uint64 amountToWithdraw = pool.amountSaved;
        uint64 feeAmount = 0;

        if (pool.locktype == LockingType.STRICTLOCK) {
            require(
                pool.startDate + pool.Duration <= uint64(block.timestamp),
                "Saving period still active"
            );

            pool.amountSaved = 0;
            pool.isGoalAccomplished = true;

            // Transfer from vault to user (vaultAuthority signs)
            SplToken.transfer(
                tx.accounts.vaultTokenAccount.key,
                tx.accounts.userTokenAccount.key,
                tx.accounts.vaultAuthority.key,
                amountToWithdraw
            );
        } else if (pool.isGoalAccomplished) {
            pool.amountSaved = 0;

            SplToken.transfer(
                tx.accounts.vaultTokenAccount.key,
                tx.accounts.userTokenAccount.key,
                tx.accounts.vaultAuthority.key,
                amountToWithdraw
            );
        } else {
            // Early withdrawal penalty
            feeAmount = LibChainCoopSaving.calculateInterest(pool.amountSaved);
            uint64 amountReturnToUser = pool.amountSaved - feeAmount;
            pool.amountSaved = 0;

            SplToken.transfer(
                tx.accounts.vaultTokenAccount.key,
                tx.accounts.userTokenAccount.key,
                tx.accounts.vaultAuthority.key,
                amountReturnToUser
            );

            // Transfer fee to feeTokenAccount
            require(chainCoopManagementAddress != address(0), "Fee manager not set");

            SplToken.transfer(
                tx.accounts.vaultTokenAccount.key,
                tx.accounts.feeTokenAccount.key,
                tx.accounts.vaultAuthority.key,
                feeAmount
            );
        }

        // Reset user balance
        userPoolBalance[signer][_poolId] = 0;

        emit Withdraw(signer, pool.tokenToSaveWith, amountToWithdraw, _poolId);

        // Remove pool from user's index map: swap-last technique using indices
        uint64 count = userPoolCount[signer];
        if (count > 0) {
            uint64 foundIndex = type(uint64).max;
            for (uint64 i = 0; i < count; i++) {
                bytes32 pid = userPoolsByIndex[signer][i];
                if (pid == _poolId) {
                    foundIndex = i;
                    break;
                }
            }
            if (foundIndex != type(uint64).max) {
                uint64 lastIndex = count - 1;
                if (foundIndex != lastIndex) {
                    // move last into position
                    bytes32 lastPid = userPoolsByIndex[signer][lastIndex];
                    userPoolsByIndex[signer][foundIndex] = lastPid;
                }
                // delete last
                delete userPoolsByIndex[signer][lastIndex];
                userPoolCount[signer] = lastIndex;
            }
        }

        // Delete pool from global mapping
        delete poolSavingPool[_poolId];
        if (totalPools > 0) {
            totalPools -= 1;
        }

        emit PoolClosed(signer, _poolId);
    }

    /* -------------------------
       Stop / Restart
       ------------------------- */
    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    function stopSaving(bytes32 _poolId) external override {
        address signer = tx.accounts.userAccount.key;
        IChainCoopSaving.SavingPool storage pool = poolSavingPool[_poolId];
        require(pool.saver == signer, "Not the pool owner");
        pool.isStoped = true;

        emit PoolStopped(signer, _poolId);
    }

    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    function restartSaving(bytes32 _poolId) external override {
        address signer = tx.accounts.userAccount.key;
        IChainCoopSaving.SavingPool storage pool = poolSavingPool[_poolId];
        require(pool.saver == signer, "Not the pool owner");
        pool.isStoped = false;

        emit PoolRestarted(signer, _poolId);
    }

    /* -------------------------
       Getters
       ------------------------- */

    function getSavingPoolCount() external view override returns (uint64) {
        return totalPools;
    }

    function getSavingPoolByIndex(bytes32 _index) external view override returns (IChainCoopSaving.SavingPool memory) {
        return poolSavingPool[_index];
    }

    // safer pattern for user pools on Solang: return count and poolId by index
    function getUserPoolCount(address _saver) external view returns (uint64) {
        return userPoolCount[_saver];
    }

    function getUserPoolIdByIndex(address _saver, uint64 _index) external view returns (bytes32) {
        require(_index < userPoolCount[_saver], "Index out of bounds");
        return userPoolsByIndex[_saver][_index];
    }

    /*
    function getSavingPoolBySaver(address _saver) external view override returns (IChainCoopSaving.SavingPool[] memory) {
        uint64 count = userPoolCount[_saver];
        IChainCoopSaving.SavingPool[] memory result = new IChainCoopSaving.SavingPool[](count);
        for (uint64 i = 0; i < count; i++) {
            bytes32 pid = userPoolsByIndex[_saver][i];
            result[i] = poolSavingPool[pid];
        }
        return result;
    }
    */
}
