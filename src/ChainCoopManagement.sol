// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ChainCoopManagement {
    address public authority;
    address public chainCoopFees;

    mapping(address => bool) public isTokenAllowed;

    event AllowToken(address indexed updator, address indexed allowedToken);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event ChainCoopFeesChanged(
        address indexed previousChainCoopFees,
        address indexed newChainCoopFees,
        address indexed ownerChanged
    );

    // --- Initialization instead of constructor ---
    @signer(authorityAccount)
    @mutableAccount(contractData)
    function initialize(address _tokenAddress, address _initialAuthority) external {
        require(_initialAuthority != address(0), "Invalid authority");
        authority = _initialAuthority;
        isTokenAllowed[_tokenAddress] = true;
    }

    @signer(authorityAccount)
    @mutableAccount(contractData)
    function transferOwnership(address newOwner) external {
        require(newOwner != address(0), "Invalid address");
        require(tx.accounts.authorityAccount.key == authority, "Not authorized");

        address oldOwner = authority;
        authority = newOwner;

        emit AdminChanged(oldOwner, newOwner);
    }

    @signer(authorityAccount)
    @mutableAccount(contractData)
    function setAllowedTokens(address _tokenAddress) external {
        require(_tokenAddress != address(0), "Invalid token");
        isTokenAllowed[_tokenAddress] = true;

        emit AllowToken(tx.accounts.authorityAccount.key, _tokenAddress);
    }

    @signer(authorityAccount)
    @mutableAccount(contractData)
    function removeAllowedTokens(address _tokenAddress) external {
        isTokenAllowed[_tokenAddress] = false;

        emit AllowToken(tx.accounts.authorityAccount.key, _tokenAddress);
    }

    @signer(authorityAccount)
    @mutableAccount(contractData)
    function setChainCoopAddress(address _chaincoopfees) external {
        require(_chaincoopfees != address(0), "Invalid address");

        address oldFees = chainCoopFees;
        chainCoopFees = _chaincoopfees;

        emit ChainCoopFeesChanged(
            oldFees,
            _chaincoopfees,
            tx.accounts.authorityAccount.key
        );
    }
}
