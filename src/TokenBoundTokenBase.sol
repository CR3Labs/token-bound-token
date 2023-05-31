// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import "./helpers/WordCodec.sol";
import "./tokens/ERC1155URIBaseUpgradeable.sol";
import "openzeppelin-contracts/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";

/**
 * @title TokenBoundToken
 * @author Mike Roth
 *
 * @dev A TokenBoundToken is an extended ERC-721/1155 where the owner of the token can be another token (721).
 * Bindable TokenBoundTokens were designed to enable attaching functionality to existing NFTs without affecting the original NFT.
 *
 * Requirements:
 *  - TokenBoundTokens can only be `unbound` if the `isPermanent` flag is set to false on mint
 *  - The `bind` method must be called by the owner (or approved) of the token being bound to
 *  - The underlying 1155 implements several additional extensions, specifically:
 *     - OpenZeppelin ERC1155Receiver: ability to set the contract as the owner of its underlying 1155 tokens
 *     - OpenZeppelin ERC155Supply: keep track of token supply to enable minting semi and non-fungible tokens
 *     - ERC1155URI: add tokenURI similar to ERC721 to support setting URI on a per-token basis
 *     - OpenZeppelin: pull payment for genesis achievemint sales and to address security concerns
 */
contract TokenBoundTokenBase is ERC1155URIBaseUpgradeable {
    using WordCodec for bytes32;

    string public name;
    string public symbol;

    event BindTokenBoundToken(
        address indexed operator,
        address indexed contractAddress,
        uint256 indexed tokenId,
        uint256 achievemintId,
        string uri
    );
    event UnbindTokenBoundToken(
        address indexed operator, address indexed contractAddress, uint256 indexed tokenId, uint256 achievemintId
    );
    event PurchaseTokenBoundToken(address indexed operator, uint256 indexed achievemintId);

    // Payee address
    address private _payee;

    // To support achievemint keys, restricts current achievemintId to 96bits
    uint96 private _achievemintId;

    // [   1 bit   |  255 bits ]
    // [ perm flag |   price   ]
    // |MSB                 LSB|
    uint256 private constant _PRICE_OFFSET = 0;
    uint256 private constant _PERMANENT_FLAG_OFFSET = 255;

    // Mapping of achievemintIds to achievemint state: prices (in wei) and permanence
    mapping(uint256 => bytes32) private _achievemintState;

    // Define an TokenBoundTokenID as the concatenation of the id and contract address
    // (this limits the number of ids to 2^96 - 1; should be enough)
    // [ 160 bits |  96 bits ]
    // [ address  |    ID    ]
    // |MSB               LSB|
    //
    // Mapping of achievemintKey -> tokenId -> bound flag
    mapping(bytes32 => mapping(uint256 => bool)) private _achievemintBindings;

    // Mapping of achievemintKey -> tokenId -> achievemint URI
    mapping(bytes32 => mapping(uint256 => string)) private _achievemintURIs;

    // Mapping of contract addresses to ownerOf(uint256) functions
    // DEV: only functions which receive a uint256 and return an address are supported
    mapping(address => string) private _contractOwnerOfFunctions;

    /**
     * @dev proxy unchained initializer
     */
    function __TokenBoundTokenBase_init_unchained(string memory name_, string memory symbol_) internal initializer {
        name = name_;
        symbol = symbol_;
    }

    /**
     * @dev Sets the payee address
     *
     * Requirements:
     * - `payee` cannot be the zero address.
     */
    function setPayee(address payee_) public virtual onlyOwner {
        require(payee_ != address(0), "BACHV: set payee to zero address");
        _payee = payee_;
    }

    /**
     * @dev return the current payee
     */
    function payee() public view virtual returns (address) {
        return _payee;
    }

    /**
     * @dev Sets ownerOf functions.
     *
     * This is necessary to enable achievemint support for non-standard NFTs which are not yet known.
     */
    function setOwnerOfFunction(address contractAddress, string memory ownerOfFunc) public virtual onlyOwner {
        _contractOwnerOfFunctions[contractAddress] = ownerOfFunc;
    }

    /**
     * @dev Mint a new achievemint token.
     *
     * Auto increments tokenId, sets the tokenURI and sets price / permanence flag
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `price` must be > 0
     * - `amount` must be > 0
     */
    function mint(address to, uint256 amount, string memory uri, uint256 price, bool permanent)
        public
        virtual
        onlyOwner
    {
        require(to != address(0), "BACHV: mint to the zero address");
        require(price >= 0, "BACHV: price must be >= 0");
        require(amount > 0, "BACHV: amount must be > 0");

        uint256 newTokenBoundTokenId = _incrementTokenBoundTokenId();

        if (bytes(uri).length > 0) {
            _setTokenURI(newTokenBoundTokenId, uri);
        }

        _setPriceAndPermanence(newTokenBoundTokenId, price, permanent);
        _mint(to, newTokenBoundTokenId, amount, "");
    }

    /**
     * @dev Batch mint achievemints
     *
     * Auto increments tokenIds, sets tokenURIs and sets price / permanence flags
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - all parameter lengths must match.
     */
    function mintBatch(
        address to,
        uint256[] memory amounts,
        string[] memory uris,
        uint256[] memory prices,
        bool[] memory permanents
    ) public virtual onlyOwner {
        require(to != address(0), "BACHV: mint to the zero address");
        require(
            (amounts.length == uris.length && uris.length == prices.length && prices.length == permanents.length),
            "BACHV: param length mismatch"
        );

        uint256[] memory ids = new uint256[](amounts.length);

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 newTokenBoundTokenId = _incrementTokenBoundTokenId();
            ids[i] = newTokenBoundTokenId;

            if (bytes(uris[i]).length > 0) {
                _setTokenURI(newTokenBoundTokenId, uris[i]);
            }

            _setPriceAndPermanence(newTokenBoundTokenId, prices[i], permanents[i]);
        }

        _mintBatch(to, ids, amounts, "");
    }

    /**
     * @dev Bind an achievemint to a token
     *
     * Transfers achievemint to contract, sets achievemint URI for this binding and increments the tokens achievemint
     * balance.
     *
     * Requirements:
     * - achievemint must not already be bound (if fungible is false)
     * - msg.sender must have a positive balance of the achievemint
     * - msg.sender must own the token receiving the achievemint
     */
    function bind(address contractAddress, uint256 tokenId, uint256 achievemintId, string memory uri) public virtual {
        require(!isBound(contractAddress, tokenId, achievemintId), "BACHV: token has achievemint");

        address operator = _msgSender();

        require(balanceOf(operator, achievemintId) > 0, "BACHV: not achievemint owner");

        require(ownsToken(contractAddress, tokenId, operator), "BACHV: not token owner");

        // transfer achievemint to contract
        _safeTransferFrom(operator, address(this), achievemintId, 1, "");

        // set uri and balances using achievemint key
        bytes32 achievemintKey = _encodeTokenBoundTokenKey(contractAddress, uint96(achievemintId));

        _achievemintURIs[achievemintKey][tokenId] = uri;
        _achievemintBindings[achievemintKey][tokenId] = true;

        emit BindTokenBoundToken(operator, contractAddress, tokenId, achievemintId, uri);
    }

    /**
     * @dev Unbind an achievemint from a token. Transfers achievemint back to nft owner, unsets achievemint URI
     * and sets bound flag to false.
     *
     * Requirements:
     * - achievemint must be bound
     * - achievemint can not be flagged as permanent
     * - sender must own the token with the bound achievemint
     */
    function unbind(address contractAddress, uint256 tokenId, uint256 achievemintId) public virtual {
        bytes32 achievemintKey = _encodeTokenBoundTokenKey(contractAddress, uint96(achievemintId));

        require(_achievemintBindings[achievemintKey][tokenId], "BACHV: not bound");
        require(!_achievemintState[achievemintId].decodeBool(_PERMANENT_FLAG_OFFSET), "BACHV: can't be unbound");

        address operator = _msgSender();

        require(ownsToken(contractAddress, tokenId, operator), "BACHV: sender does not own token");

        // unbind the achievemint
        _achievemintURIs[achievemintKey][tokenId] = "";
        _achievemintBindings[achievemintKey][tokenId] = false;

        // transfer achievemint back to owner
        _safeTransferFrom(address(this), operator, achievemintId, 1, "");

        emit UnbindTokenBoundToken(operator, contractAddress, tokenId, achievemintId);
    }

    /**
     * @dev Purchase an achievemint
     *
     * If the contract owner address contains a balance for this achievemintId, transfer the achievemint to the sender.
     *
     * This implementation uses a PullPayment strategy to transfer the exact amount to the PulPayment contract.
     * Checking the exact balance is fine for our purposes because all prices will be a fixed round number set directly
     * by the FP team. Unbindable achievemints can be traded on open markets and will not require this purchase
     * functionality.
     *
     * Requirements:
     * - payee must be set
     * - contract owner must have a balance of the achievemint
     * - correct payment value must be sent
     */
    function purchase(uint256 achievemintId) public payable virtual {
        address operator = _msgSender();
        address owner_ = owner();
        address payee_ = payee();

        require(payee_ != address(0), "BACHV: payee has not been set");

        require(balanceOf(owner_, achievemintId) > 0, "BACHV: purchase not available");

        // take payment using _asyncTransfer
        require(
            msg.value == _achievemintState[achievemintId].decodeUint255(_PRICE_OFFSET), "BACHV: wrong payment value"
        );
        _asyncTransfer(payee_, msg.value);

        // transfer achievemint to address
        _safeTransferFrom(owner_, operator, achievemintId, 1, "");

        emit PurchaseTokenBoundToken(operator, achievemintId);
    }

    /**
     * @dev Convenience function to Purchase and Bind in one call
     */
    function purchaseAndBind(uint256 achievemintId, address contractAddress, uint256 tokenId, string memory uri)
        public
        payable
        virtual
    {
        purchase(achievemintId);
        bind(contractAddress, tokenId, achievemintId, uri);
    }

    /**
     * @dev Return the price of an achievemint
     */
    function priceOf(uint256 achievemintId) public view virtual returns (uint256) {
        return _achievemintState[achievemintId].decodeUint255(_PRICE_OFFSET);
    }

    /**
     * @dev Return the achievemint permanent flag
     */
    function isPermanent(uint256 achievemintId) public view virtual returns (bool) {
        return _achievemintState[achievemintId].decodeBool(_PERMANENT_FLAG_OFFSET);
    }

    /**
     * @dev Return whether or not an achievemint is bound to a token
     */
    function isBound(address contractAddress, uint256 tokenId, uint256 achievemintId)
        public
        view
        virtual
        returns (bool)
    {
        bytes32 achievemintKey = _encodeTokenBoundTokenKey(contractAddress, uint96(achievemintId));
        return _achievemintBindings[achievemintKey][tokenId];
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
        require(contractAddress != address(0), "BACHV: invalid contract address");
        string memory func = (bytes(_contractOwnerOfFunctions[contractAddress]).length != 0)
            ? _contractOwnerOfFunctions[contractAddress]
            : "ownerOf(uint256)";
        bytes memory payload = abi.encodeWithSignature(func, tokenId);
        (bool success, bytes memory returnData) = contractAddress.staticcall(payload);
        require(success, "BACHV: can't determine owner");
        return (_bytesToAddress(returnData) == owner);
    }

    /**
     * @dev Return a bound achievemints URI
     */
    function achievemintURI(address contractAddress, uint256 tokenId, uint256 achievemintId)
        public
        view
        virtual
        returns (string memory)
    {
        bytes32 achievemintKey = _encodeTokenBoundTokenKey(contractAddress, uint96(achievemintId));
        return _achievemintURIs[achievemintKey][tokenId];
    }

    /**
     * @dev Increments the current achievemintId
     */
    function _incrementTokenBoundTokenId() internal returns (uint96) {
        _achievemintId += 1;
        return _achievemintId;
    }

    /**
     * @dev Set the price and permanence for an achievemint
     */
    function _setPriceAndPermanence(uint256 achievemintId, uint256 price, bool permanent) private {
        bytes32 achievemintState;

        _achievemintState[achievemintId] =
            achievemintState.insertUint255(price, _PRICE_OFFSET).insertBool(permanent, _PERMANENT_FLAG_OFFSET);
    }

    /**
     * @dev convert bytes to an address
     */
    function _bytesToAddress(bytes memory bys) private pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 32))
        }
    }

    /**
     * @dev Encode contract/achievemintId to key
     *
     * Layout is: | 20 byte address | 12 byte ID |
     */
    function _encodeTokenBoundTokenKey(address contractAddress, uint256 achievemintId) private pure returns (bytes32) {
        bytes32 serialized;

        serialized |= bytes32(uint256(achievemintId));
        serialized |= bytes32(uint256(uint160(contractAddress))) << (12 * 8);

        return serialized;
    }

    uint256[50] private __gap;
}
