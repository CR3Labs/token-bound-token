pragma solidity ^0.8.13;

import "./TokenBoundTokenBase.sol";

contract TokenBoundToken is TokenBoundTokenBase {
    event CreateTokenBoundToken(address owner, string name, string symbol);

    function __TokenBoundToken_init(string memory _name, string memory _symbol, string memory baseURI)
        external
        initializer
    {
        __TokenBoundToken_init_unchained(_name, _symbol, baseURI);
        emit CreateTokenBoundToken(_msgSender(), _name, _symbol);
    }

    function __TokenBoundToken_init_unchained(string memory _name, string memory _symbol, string memory baseURI)
        internal
    {
        __Ownable_init_unchained();
        __PullPayment_init_unchained();
        __ERC165_init_unchained();
        __ERC1155Receiver_init_unchained();
        __ERC1155Holder_init_unchained();
        __ERC1155_init_unchained("");
        __TokenBoundTokenBase_init_unchained(_name, _symbol);
        _setBaseURI(baseURI);
    }

    uint256[50] private __gap;
}
