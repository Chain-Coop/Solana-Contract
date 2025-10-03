contract ChainCoopManagement {
    address public authority;
    address public chainCoopFees;

    // Events
    event AllowToken(address _updator, address _allowedToken);
    event AdminChanged(address previousAdmin, address newAdmin);
    event ChainCoopFeesChanged(
        address indexed previousChainCoopFees,
        address indexed newChainCoopFees,
        address indexed _ownerChanged
    );

    // Mapping - Solana stores these as PDAs
    mapping(address => bool) public isTokenAllowed;

    modifier onlyAllowedTokens(address _tokenAddress) {
        require(isTokenAllowed[_tokenAddress], "Token not allowed");
        _;
    }

    constructor(address _tokenAddress, address initial_authority) {
        authority = initial_authority;
        isTokenAllowed[_tokenAddress] = true;
    }

    @signer(authorityAccount)
    function transferOwnership(address newOwner) external {
        require(newOwner != address(0), "Invalid address");
        address oldOwner = authority;
        authority = newOwner;
        emit AdminChanged(oldOwner, newOwner);
    }

    @signer(authorityAccount)
    function setAllowedTokens(address _tokenAddress) external {
        require(_tokenAddress != address(0), "Invalid token address");
        isTokenAllowed[_tokenAddress] = true;
        emit AllowToken(tx.accounts.authorityAccount.key, _tokenAddress);
    }

    @signer(authorityAccount)
    function removeAllowedTokens(address _tokenAddress) external {
        isTokenAllowed[_tokenAddress] = false;
        emit AllowToken(tx.accounts.authorityAccount.key, _tokenAddress);
    }

    @signer(authorityAccount)
    function setChainCoopAddress(address _chaincoopfees) external {
        require(_chaincoopfees != address(0), "Invalid address");
        address oldFees = chainCoopFees;
        chainCoopFees = _chaincoopfees;
        emit ChainCoopFeesChanged(
            oldFees, _chaincoopfees, tx.accounts.authorityAccount.key
        );
    }
}