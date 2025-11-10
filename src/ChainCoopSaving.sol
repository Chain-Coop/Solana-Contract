// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./lib/spl_token.sol";

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

library LibChainCoopSaving {
    function generatePoolIndex(address user, uint64 index) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, index));
    }

    function calculateInterest(uint64 _principal) internal pure returns (uint64) {
        uint64 interest = (_principal * 3) / 100; // 3% interest
        return interest;
    }
}

@program_id("948Qgeb7fGxH7tZ8uCdPyEEBw2zm9vk83e57Besee4yb")
contract ChainCoopSaving is IChainCoopSaving {
    using LibChainCoopSaving for *;

    // Storage
    mapping(bytes32 => IChainCoopSaving.SavingPool) public poolSavingPool;
    // Avoid dynamic array push/pop issues on Windows/Solang by using an indexed mapping
    mapping(address => mapping(uint64 => bytes32)) private userPoolsByIndex;
    mapping(address => uint64) private userPoolCount; // number of pools per user

    mapping(address => mapping(bytes32 => uint64)) public userPoolBalance;

    uint64 private totalPools;

    // Owner (program admin)
    address public owner;

    // Token allowlist management
    mapping(address => bool) private allowedTokens;
    bool public tokenFilteringEnabled;

    // Fee recipient address
    address public feeRecipient;

    // Events
    event PoolOpened(address indexed saver, bytes32 poolId, uint64 amount, uint64 poolIndex);
    event PoolUpdated(address indexed saver, bytes32 poolId, uint64 newAmount);
    event Withdraw(address indexed saver, address token, uint64 amount, bytes32 poolId, uint64 feeCharged);
    event PoolClosed(address indexed saver, bytes32 poolId);
    event PoolStopped(address indexed saver, bytes32 poolId);
    event PoolRestarted(address indexed saver, bytes32 poolId);
    event TokenFilteringChanged(bool enabled);
    event AllowedTokenSet(address indexed token, bool allowed);
    event FeeRecipientSet(address indexed newRecipient);

    // -------------------------
    // Initialization (Solana-friendly)
    // -------------------------
    @signer(ownerAccount)
    function initialize(address _feeRecipient) external {
        require(owner == address(0), "Already initialized");
        require(tx.accounts.ownerAccount.key != address(0), "Invalid owner");
        owner = tx.accounts.ownerAccount.key;
        feeRecipient = _feeRecipient;
        tokenFilteringEnabled = false; // Default: accept all tokens
        totalPools = 0;
    }

    /* -------------------------
       Owner Management Functions
       ------------------------- */

    @signer(ownerAccount)
    function setAllowedToken(address token, bool allowed) external {
        require(tx.accounts.ownerAccount.key == owner, "Only owner can set allowed tokens");
        require(token != address(0), "Invalid token address");
        allowedTokens[token] = allowed;
        emit AllowedTokenSet(token, allowed);
    }

    @signer(ownerAccount)
    function setTokenFilteringEnabled(bool enabled) external {
        require(tx.accounts.ownerAccount.key == owner, "Only owner can change filtering");
        tokenFilteringEnabled = enabled;
        emit TokenFilteringChanged(enabled);
    }

    @signer(ownerAccount)
    function setFeeRecipient(address _feeRecipient) external {
        require(tx.accounts.ownerAccount.key == owner, "Only owner can set fee recipient");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
        emit FeeRecipientSet(_feeRecipient);
    }

    /* -------------------------
       Helper / Internal
       ------------------------- */

    function _isTokenAllowed(address token) internal view returns (bool) {
        if (!tokenFilteringEnabled) {
            return true; // Accept all tokens if filtering is disabled
        }
        return allowedTokens[token];
    }

    function _makePoolId(address saver, uint64 index, uint64 startDate) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(saver, index, startDate));
    }

    function _checkGoalAccomplished(IChainCoopSaving.SavingPool storage pool) internal view returns (bool) {
        if (pool.locktype == LockingType.FLEXIBLE) {
            return true; // Flexible is always accomplished
        }
        // For LOCK and STRICTLOCK, check if duration has passed
        return pool.startDate + pool.duration <= uint64(block.timestamp);
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
        
        // Validate duration for LOCK and STRICTLOCK types
        if (_locktype == LockingType.LOCK || _locktype == LockingType.STRICTLOCK) {
            require(_duration > 0, "Duration must be > 0 for LOCK/STRICTLOCK");
        }

        // create an index for this user's pool
        uint64 userIndex = userPoolCount[signer];
        uint64 startDate = uint64(block.timestamp);

        bytes32 poolId = _makePoolId(signer, userIndex, startDate);

        IChainCoopSaving.SavingPool storage pool = poolSavingPool[poolId];

        pool.saver = signer;
        pool.tokenToSaveWith = _tokenTosaveWith;
        pool.reason = bytes32(0);
        pool.poolIndex = poolId;
        pool.startDate = startDate;
        pool.duration = _duration;
        pool.amountSaved = _savedAmount;
        pool.locktype = _locktype;
        pool.isGoalAccomplished = false;
        pool.isStopped = false;

        // Store mapping index
        userPoolsByIndex[signer][userIndex] = poolId;
        userPoolCount[signer] = userIndex + 1;

        // Update totals
        totalPools += 1;

        // Track user's balance for this pool
        userPoolBalance[signer][poolId] = _savedAmount;

        // Transfer tokens from user to vault
        SplToken.transfer(
            tx.accounts.userTokenAccount.key,
            tx.accounts.vaultTokenAccount.key,
            tx.accounts.userAccount.key,
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

        require(pool.saver != address(0), "Pool does not exist");
        require(pool.saver == signer, "Not the pool owner");
        require(!pool.isStopped, "Pool is stopped");
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
        require(!pool.isStopped, "Pool is stopped");
        require(pool.amountSaved > 0, "No funds to withdraw");

        uint64 amountToWithdraw = pool.amountSaved;
        uint64 feeAmount = 0;
        bool goalAccomplished = _checkGoalAccomplished(pool);

        // STRICTLOCK: Must wait until duration passes
        if (pool.locktype == LockingType.STRICTLOCK) {
            require(goalAccomplished, "Saving period still active for STRICTLOCK");
            
            pool.amountSaved = 0;
            pool.isGoalAccomplished = true;

            // Transfer from vault to user (no fee)
            SplToken.transfer(
                tx.accounts.vaultTokenAccount.key,
                tx.accounts.userTokenAccount.key,
                tx.accounts.vaultAuthority.key,
                amountToWithdraw
            );
        }
        // LOCK: Can withdraw early with fee, or without fee after duration
        else if (pool.locktype == LockingType.LOCK) {
            if (goalAccomplished) {
                // Duration passed, no fee
                pool.amountSaved = 0;
                pool.isGoalAccomplished = true;

                SplToken.transfer(
                    tx.accounts.vaultTokenAccount.key,
                    tx.accounts.userTokenAccount.key,
                    tx.accounts.vaultAuthority.key,
                    amountToWithdraw
                );
            } else {
                // Early withdrawal, charge fee
                require(feeRecipient != address(0), "Fee recipient not set");
                
                feeAmount = LibChainCoopSaving.calculateInterest(pool.amountSaved);
                uint64 amountReturnToUser = pool.amountSaved - feeAmount;
                pool.amountSaved = 0;

                // Transfer to user (minus fee)
                SplToken.transfer(
                    tx.accounts.vaultTokenAccount.key,
                    tx.accounts.userTokenAccount.key,
                    tx.accounts.vaultAuthority.key,
                    amountReturnToUser
                );

                // Transfer fee
                SplToken.transfer(
                    tx.accounts.vaultTokenAccount.key,
                    tx.accounts.feeTokenAccount.key,
                    tx.accounts.vaultAuthority.key,
                    feeAmount
                );
            }
        }
        // FLEXIBLE: Always no fee
        else {
            pool.amountSaved = 0;
            pool.isGoalAccomplished = true;

            SplToken.transfer(
                tx.accounts.vaultTokenAccount.key,
                tx.accounts.userTokenAccount.key,
                tx.accounts.vaultAuthority.key,
                amountToWithdraw
            );
        }

        // Reset user balance
        userPoolBalance[signer][_poolId] = 0;

        emit Withdraw(signer, pool.tokenToSaveWith, amountToWithdraw, _poolId, feeAmount);

        // Remove pool from user's index map: swap-last technique
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
                    bytes32 lastPid = userPoolsByIndex[signer][lastIndex];
                    userPoolsByIndex[signer][foundIndex] = lastPid;
                }
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
        
        require(pool.saver != address(0), "Pool does not exist");
        require(pool.saver == signer, "Not the pool owner");
        require(!pool.isStopped, "Pool already stopped");
        
        pool.isStopped = true;

        emit PoolStopped(signer, _poolId);
    }

    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    function restartSaving(bytes32 _poolId) external override {
        address signer = tx.accounts.userAccount.key;
        IChainCoopSaving.SavingPool storage pool = poolSavingPool[_poolId];
        
        require(pool.saver != address(0), "Pool does not exist");
        require(pool.saver == signer, "Not the pool owner");
        require(pool.isStopped, "Pool is not stopped");
        
        pool.isStopped = false;

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

    function getUserPoolCount(address _saver) external view returns (uint64) {
        return userPoolCount[_saver];
    }

    function getUserPoolIdByIndex(address _saver, uint64 _index) external view returns (bytes32) {
        require(_index < userPoolCount[_saver], "Index out of bounds");
        return userPoolsByIndex[_saver][_index];
    }

    function isTokenAllowed(address token) external view returns (bool) {
        return _isTokenAllowed(token);
    }
}