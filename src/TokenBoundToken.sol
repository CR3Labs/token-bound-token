// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import "openzeppelin/token/ERC721/utils/ERC721Holder.sol";
import "openzeppelin/security/PullPayment.sol";
import "./tokens/ERC721Base.sol";

/**
 * @title TokenBoundToken
 * @author Mike Roth
 *
 * @dev A Token-Bound Token is an extended ERC-721 where the owner of the token can be another token (721).
 * Bindable Tokens were designed to enable attaching functionality to existing NFTs without affecting the original NFT.
 *
 * Requirements:
 *  - Token Bound Tokens can only be `unbound` if the `isSoulbound` flag is set to false
 *  - The `bind` method must be called by the owner (or approved) of the token being bound to
 *  - Implements several additional extensions, specifically:
 *     - OpenZeppelin ERC721Holder: ability to set the contract as the owner of its underlying 721 tokens
 *     - OpenZeppelin: pull payment for genesis tbt sales and to address security concerns
 */

contract TokenBoundToken is ERC721Holder, PullPayment, ERC721Base {
    struct Token {
        address contractAddress;
        uint256 tokenId;
        bool exists;
    }

    event TokenBound(address indexed operator, Token indexed token, uint256 indexed tbtId);
    event TokenUnbound(address indexed operator, Token indexed token, uint256 indexed tbtId);
    event TokenPurchased(address indexed operator, uint256 indexed tbtId);

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Payee address
    address private _payee;

    // Soulbound flag
    bool private _isSoulbound;

    // Price
    uint256 private _price;

    // TokenIds
    uint256 private _tbtId;

    // Mapping of tbtId -> Token
    mapping(uint256 => Token) private _bindings;

    // Mapping of contract addresses to ownerOf(uint256) functions
    // DEV: only functions which receive a uint256 and return an address are supported
    mapping(address => string) private _contractOwnerOfFunctions;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name, string memory symbol, address payee_, bool isSoulbound_, uint256 price_)
        ERC721(name, symbol)
    {
        _payee = payee_;
        _isSoulbound = isSoulbound_;
        _price = price_;
    }

    /**
     * @dev Sets the payee address
     *
     * Requirements:
     * - `payee` cannot be the zero address.
     */
    function setPayee(address payee_) public virtual onlyOwner {
        require(payee_ != address(0), "TBT: set payee to zero address");
        _payee = payee_;
    }

    /**
     * @dev return the current payee
     */
    function payee() public view virtual returns (address) {
        return _payee;
    }

    /**
     * @dev Sets the price
     *
     * Requirements:
     * - `price` cannot be the zero address.
     */
    function setPrice(uint256 price_) public virtual onlyOwner {
        require(price_ > 0, "TBT: price must be > 0");
        _price = price_;
    }

    /**
     * @dev return the current price
     */
    function price() public view virtual returns (uint256) {
        return _price;
    }

    /**
     * @dev Sets ownerOf functions.
     *
     * This is necessary to enable tbt support for non-standard NFT owner functions
     */
    function setOwnerOfFunction(address contractAddress, string memory ownerOfFunc) public virtual onlyOwner {
        _contractOwnerOfFunctions[contractAddress] = ownerOfFunc;
    }

    /**
     * @dev Mint a new tbt token as an owner
     *
     * Auto increments tokenId
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function ownerMint(address to) public virtual onlyOwner returns (uint256) {
        require(to != address(0), "TBT: mint to the zero address");
        uint256 newTokenBoundTokenId = _incrementTokenBoundTokenId();
        _safeMint(to, newTokenBoundTokenId);
        return newTokenBoundTokenId;
    }

    /**
     * @dev Bind a token
     *
     * Transfers token to contract
     *
     * Requirements:
     * - token must not already be bound
     * - msg.sender must own the token
     * - msg.sender must own the token being bound to
     */
    function bind(address contractAddress, uint256 tokenId, uint256 tbtId) public virtual {
        require(!isBound(tbtId), "TBT: token already bound");

        address operator = _msgSender();

        require(ownsToken(address(this), tbtId, operator), "TBT: sender not token owner");
        require(ownsToken(contractAddress, tokenId, operator), "TBT: sender not token bindee owner");

        // transfer tbt to contract
        safeTransferFrom(operator, address(this), tbtId);

        // set bound
        Token memory token = Token(contractAddress, tokenId, true);
        _bindings[tbtId] = token;

        emit TokenBound(operator, token, tbtId);
    }

    /**
     * @dev Unbind a tbt from a token. Transfers tbt back to nft owner and sets bound flag to false.
     *
     * Requirements:
     * - tbt must be bound
     * - tbt can not be flagged as soulbound
     * - sender must own the token with the bound tbt
     */
    function unbind(uint256 tbtId) public virtual {
        require(_bindings[tbtId].exists, "TBT: not bound");
        require(!_isSoulbound, "TBT: soulbound");

        address operator = _msgSender();
        Token memory token = _bindings[tbtId];

        require(ownsToken(token.contractAddress, token.tokenId, operator), "TBT: sender not token bindee owner");

        // unbind the tbt
        delete _bindings[tbtId];

        // transfer tbt back to owner
        _safeTransfer(address(this), operator, tbtId, "");

        emit TokenUnbound(operator, token, tbtId);
    }

    /**
     * @dev Mint a tbt
     *
     * If the contract owner address contains a balance for this tbtId, transfer the tbt to the sender.
     *
     * This implementation uses a PullPayment strategy to transfer the exact amount to the PullPayment contract.
     * Checking the exact balance is fine for our purposes because all prices will be a fixed round number set directly
     * by the team. Unbindable tbts can be traded on open markets and will not require this purchase
     * functionality.
     *
     * Requirements:
     * - payee must be set
     * - contract owner must have a balance of the tbt
     * - correct payment value must be sent
     */
    function mint() public payable virtual returns (uint256) {
        address payee_ = payee();

        require(payee_ != address(0), "TBT: payee has not been set");

        // take payment using _asyncTransfer
        require(msg.value == _price, "TBT: wrong payment value");
        _asyncTransfer(payee_, msg.value);

        // mint a new token
        uint256 newTbtId = _incrementTokenBoundTokenId();
        _safeMint(msg.sender, newTbtId);

        return newTbtId;
    }

    /**
     * @dev Convenience function to Purchase and Bind in one call
     */
    function mintAndBind(address contractAddress, uint256 tokenId) public payable virtual {
        uint256 tbtId = mint();
        bind(contractAddress, tokenId, tbtId);
    }

    /**
     * @dev Return the tbt soulbound flag
     */
    function isSoulbound() public view returns (bool) {
        return _isSoulbound;
    }

    /**
     * @dev Return whether or not a tbt is bound
     */
    function isBound(uint256 tbtId) public view returns (bool) {
        return _bindings[tbtId].exists;
    }

    /**
     * @dev Return the token this tbt is bound to
     */
    function boundToken(uint256 tbtId) public view returns (Token memory) {
        require(tbtId > 0, "TBT: tokenId must be > 0");
        return _bindings[tbtId];
    }

    /**
     * @dev Check if an NFT is owned by msg.sender. Security vulnerabilities of this function are mitigated
     * by using a `staticcall` to the external token contract.
     *
     * Requirements:
     * - `contractAddress` cannot be the zero address.
     * - must be a successful staticcall
     */
    function ownsToken(address contractAddress, uint256 tokenId, address owner) public view virtual returns (bool) {
        require(contractAddress != address(0), "TBT: invalid contract address");
        string memory func = (bytes(_contractOwnerOfFunctions[contractAddress]).length != 0)
            ? _contractOwnerOfFunctions[contractAddress]
            : "ownerOf(uint256)";
        bytes memory payload = abi.encodeWithSignature(func, tokenId);
        (bool success, bytes memory returnData) = contractAddress.staticcall(payload);
        require(success, "TBT: can't determine owner");
        return (_bytesToAddress(returnData) == owner);
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`.
     */
    function _baseURI() internal pure override returns (string memory) {
        return "";
    }

    /**
     * @dev Increments the current tbtId
     */
    function _incrementTokenBoundTokenId() internal returns (uint256) {
        _tbtId += 1;
        return _tbtId;
    }

    /**
     * @dev convert bytes to an address
     */
    function _bytesToAddress(bytes memory bys) private pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 32))
        }
    }
}
