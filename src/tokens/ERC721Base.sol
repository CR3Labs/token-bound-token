// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "openzeppelin/token/ERC721/ERC721.sol";
import "openzeppelin/access/Ownable.sol";

abstract contract ERC721Base is ERC721, Ownable {}
