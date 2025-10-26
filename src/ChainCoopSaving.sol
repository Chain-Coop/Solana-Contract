// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./ChainCoopManagement.sol";
import "./lib/spl_token.sol";
import {AccountMeta, AccountInfo} from "solana";
import {IChainCoopSaving} from "./interface/IChainCoopSaving.sol";
import {LibChainCoopSaving} from "./lib/LibChainCoopSaving.sol";

// Solana-specific: Program ID for the ChainCoop contract
@program_id("HSgbc9ZehSwuPf82se5KZ8UT3zHfbMQpFARFa2456YU7")

contract ChainCoopSaving is IChainCoopSaving, ChainCoopManagement {
    // Reentrancy guard state
    uint8 private _status;
    uint8 private constant _NOT_ENTERED = 1;
    uint8 private constant _ENTERED = 2;

    modifier nonReentrant() {
        require(_status != _ENTERED, "Reentrancy detected");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // Events
    event OpenSavingPool(
        address indexed user,
        address indexed _tokenAddress,
        uint64 _index,
        uint64 initialAmount,
        uint64 startTime,
        LockingType lockType,
        uint64 duration,
        bytes32 _poolId
    );
    event Withdraw(
        address indexed user,
        address indexed _tokenAddress,
        uint64 amount,
        bytes32 _poolId
    );
    event UpdateSaving(
        address indexed user,
        address indexed _tokenAddress,
        uint64 amount,
        bytes32 _poolId
    );
    event RestartSaving(address _poolOwner, bytes32 _poolId);
    event StopSaving(address _poolOwner, bytes32 _poolId);
    event PoolClosed(address indexed user, bytes32 indexed poolId);

    struct Contribution {
        address tokenAddress;
        uint64 amount;
    }

    // Mappings - stored as PDAs on Solana
    mapping(bytes32 => SavingPool) public poolSavingPool;
    mapping(address => mapping(bytes32 => uint64)) public userPoolBalance;
    mapping(address => bytes32[]) public userContributedPools;

    // Pool Count
    uint64 public poolCount;

    constructor(address _tokenAddress, address _initialOwner)
        ChainCoopManagement(_tokenAddress, _initialOwner)
    {
        require(_initialOwner != address(0), "Invalid owner");
        _status = _NOT_ENTERED;
        poolCount = 0;
    }

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
        string calldata _reason,
        LockingType _locktype,
        uint64 _duration
    ) external override onlyAllowedTokens(_tokenTosaveWith) {
        require(_savedAmount > 0, "Amount must be greater than zero");
        require(_duration > 0, "Duration must be greater than zero");

        address signer = tx.accounts.userAccount.key;
        uint64 _index = poolCount;
        bool accomplished = false;
        if (_locktype == LockingType.FLEXIBLE) {
            accomplished = true;
        }

        uint64 _starttime = uint64(block.timestamp);

        bytes32 _poolId = LibChainCoopSaving.generatePoolIndex(
            signer, _starttime, _savedAmount
        );

        // Ensure pool doesn't already exist
        require(
            poolSavingPool[_poolId].saver == address(0), "Pool already exists"
        );

        // Solana: Use SPL Token transfer via CPI
        SplToken.transfer(
            tx.accounts.userTokenAccount.key,
            tx.accounts.vaultTokenAccount.key,
            tx.accounts.owner.key,
            _savedAmount
        );

        SavingPool memory pool = SavingPool({
            saver: signer,
            tokenToSaveWith: _tokenTosaveWith,
            Reason: _reason,
            poolIndex: _poolId,
            startDate: _starttime,
            Duration: _duration,
            amountSaved: _savedAmount,
            locktype: _locktype,
            isGoalAccomplished: accomplished,
            isStoped: false
        });

        poolCount++;
        poolSavingPool[_poolId] = pool;
        userContributedPools[signer].push(_poolId);
        userPoolBalance[signer][_poolId] += _savedAmount;

        emit OpenSavingPool(
            signer,
            _tokenTosaveWith,
            _index,
            _savedAmount,
            _starttime,
            _locktype,
            _duration,
            _poolId
        );
    }

    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    @mutableAccount(userPoolBalance)
    @account(userTokenAccount)
    @account(vaultTokenAccount)
    function updateSaving(bytes32 _poolId, uint64 _amount) external override {
        address signer = tx.accounts.userAccount.key;
        SavingPool storage pool = poolSavingPool[_poolId];

        require(pool.saver != address(0), "Pool does not exist");
        require(pool.saver == signer, "Not pool owner");
        require(!pool.isStoped, "Pool is stopped");
        require(
            pool.locktype != LockingType.STRICTLOCK,
            "Cannot update strict lock savings"
        );
        require(_amount > 0, "Amount must be greater than zero");

        // Transfer tokens to vault
        SplToken.transfer(
            tx.accounts.userTokenAccount.key,
            tx.accounts.vaultTokenAccount.key,
            tx.accounts.userAccount.key,
            _amount
        );

        pool.amountSaved += _amount;
        userPoolBalance[signer][_poolId] += _amount;

        // Check if goal is accomplished for LOCK type
        if (pool.locktype == LockingType.LOCK) {
            if (pool.startDate + pool.Duration <= uint64(block.timestamp)) {
                pool.isGoalAccomplished = true;
            }
        }

        emit UpdateSaving(signer, pool.tokenToSaveWith, _amount, pool.poolIndex);
    }

    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    function stopSaving(bytes32 _poolId) external override {
        address signer = tx.accounts.userAccount.key;
        SavingPool storage pool = poolSavingPool[_poolId];

        require(pool.saver != address(0), "Pool does not exist");
        require(pool.saver == signer, "Not pool owner");
        require(!pool.isStoped, "Pool already stopped");

        pool.isStoped = true;
        emit StopSaving(signer, _poolId);
    }

    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    function restartSaving(bytes32 _poolId) external override {
        address signer = tx.accounts.userAccount.key;
        SavingPool storage pool = poolSavingPool[_poolId];

        require(pool.saver != address(0), "Pool does not exist");
        require(pool.saver == signer, "Not pool owner");
        require(pool.isStoped, "Pool is not stopped");

        pool.isStoped = false;
        emit RestartSaving(signer, _poolId);
    }

    @signer(userAccount)
    @mutableAccount(poolSavingPool)
    @mutableAccount(userContributedPools)
    @mutableAccount(userPoolBalance)
    @account(userTokenAccount)
    @account(vaultTokenAccount)
    @account(vaultAuthority)
    @account(feeTokenAccount)
    function withdraw(bytes32 _poolId) external override nonReentrant {
        address signer = tx.accounts.userAccount.key;
        SavingPool storage pool = poolSavingPool[_poolId];

        require(pool.saver != address(0), "Pool does not exist");
        require(pool.saver == signer, "Not pool owner");
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

            // Transfer from vault to user
            SplToken.transfer(
                tx.accounts.vaultTokenAccount.key,
                tx.accounts.userTokenAccount.key,
                tx.accounts.vaultAuthority.key,
                amountToWithdraw
            );
        } else if (pool.isGoalAccomplished) {
            pool.amountSaved = 0;

            // Transfer from vault to user
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

            // Transfer to user
            SplToken.transfer(
                tx.accounts.vaultTokenAccount.key,
                tx.accounts.userTokenAccount.key,
                tx.accounts.vaultAuthority.key,
                amountReturnToUser
            );

            // Transfer fee
            require(chainCoopFees != address(0), "Fee address not set");
            SplToken.transfer(
                tx.accounts.vaultTokenAccount.key,
                tx.accounts.feeTokenAccount.key,
                tx.accounts.vaultAuthority.key,
                feeAmount
            );
        }

        emit Withdraw(
            signer, pool.tokenToSaveWith, amountToWithdraw, pool.poolIndex
        );

        // Clean up storage
        delete userPoolBalance[signer][_poolId];

        bytes32[] storage userPools = userContributedPools[signer];
        for (uint64 i = 0; i < userPools.length; i++) {
            if (userPools[i] == _poolId) {
                userPools[i] = userPools[userPools.length - 1];
                userPools.pop();
                break;
            }
        }

        delete poolSavingPool[_poolId];

        emit PoolClosed(signer, _poolId);
    }

    function getSavingPoolCount() external view override returns (uint64) {
        return poolCount;
    }

    function getSavingPoolByIndex(bytes32 _index)
        external
        view
        override
        returns (SavingPool memory)
    {
        return poolSavingPool[_index];
    }

    function getSavingPoolBySaver(address _saver)
        external
        view
        override
        returns (SavingPool[] memory pools)
    {
        uint32 userPoolCount = uint32(userContributedPools[_saver].length);
        pools = new SavingPool[](userPoolCount);

        for (uint32 i = 0; i < userPoolCount; i++) {
            bytes32 poolId = userContributedPools[_saver][i];
            pools[i] = poolSavingPool[poolId];
        }
    }

    function getUserContributions(address _saver)
        external
        view
        returns (Contribution[] memory contributions)
    {
        uint32 userPoolCount = uint32(userContributedPools[_saver].length);
        contributions = new Contribution[](userPoolCount);

        for (uint32 i = 0; i < userPoolCount; i++) {
            bytes32 poolId = userContributedPools[_saver][i];
            SavingPool memory pool = poolSavingPool[poolId];

            contributions[i] = Contribution({
                tokenAddress: pool.tokenToSaveWith,
                amount: pool.amountSaved
            });
        }
    }

    @signer(authorityAccount)
    @mutableAccount(poolSavingPool)
    @mutableAccount(userContributedPools)
    @mutableAccount(userPoolBalance)
    function transferOwnership(address newOwner) external {
        require(msg.sender == authority, "Not authorized");
        require(newOwner != address(0), "Invalid address");
        emit AdminChanged(authority, newOwner);
        authority = newOwner;
    }
}
