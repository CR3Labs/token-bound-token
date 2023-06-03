// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/mock/MockERC721.sol";
import "../src/TokenBoundToken.sol";

contract CounterTest is Test {
    TokenBoundToken public tbt;
    TokenBoundToken public sbTbt;
    MockERC721 public mockToken;

    function setUp() public {
        tbt = new TokenBoundToken("Test Token", "TBT", address(this), false, 80000000000000000);
        sbTbt = new TokenBoundToken("Test Soulbound Token", "SBTBT", address(this), true, 80000000000000000);
        mockToken = new MockERC721();
    }

    function testOwnerMintToken() public {
        address user1 = vm.addr(1);
        // address user2 = vm.addr(2);

        uint256 tbtId = tbt.ownerMint(user1);
        uint256 mockTokenId = mockToken.mint(user1, 1);

        assertEq(mockToken.ownerOf(mockTokenId), user1);
        assertEq(tbt.ownerOf(tbtId), user1);
    }

    function testMintToken() public {
        address user1 = vm.addr(1);

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        uint256 tbtId = tbt.mint{value: 80000000000000000}();

        assertEq(tbt.ownerOf(tbtId), user1);
        assertEq(user1.balance, 0.92 ether);
    }

    function testBindTokenNonOwnerFails() public {
        address user1 = vm.addr(1);

        uint256 tbtId = tbt.ownerMint(user1);
        uint256 mockTokenId = mockToken.mint(user1, 1);

        address contractAddress = address(mockToken);
        uint256 tokenId = mockTokenId;

        vm.expectRevert("TBT: sender not token owner");
        tbt.bind(contractAddress, tokenId, tbtId);

        bool bound = tbt.isBound(tbtId);
        assertEq(bound, false);
    }

    function testBindTokenNonTokenOwnerFails() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);

        uint256 tbtId = tbt.ownerMint(user2);
        uint256 mockTokenId = mockToken.mint(user1, 1);
        // uint256 mockTokenId2 = mockToken.mint(user2, 2);

        address contractAddress = address(mockToken);
        uint256 tokenId = mockTokenId;

        vm.prank(user2);
        vm.expectRevert("TBT: sender not token bindee owner");
        tbt.bind(contractAddress, tokenId, tbtId);

        bool bound = tbt.isBound(tbtId);
        assertEq(bound, false);
    }

    function testBindToken() public {
        address user1 = vm.addr(1);

        uint256 tbtId = tbt.ownerMint(user1);
        uint256 mockTokenId = mockToken.mint(user1, 1);

        address contractAddress = address(mockToken);
        uint256 tokenId = mockTokenId;

        // successful bind for user 1
        vm.prank(user1);
        tbt.bind(contractAddress, tokenId, tbtId);

        bool bound1 = tbt.isBound(tbtId);
        assertEq(bound1, true);
    }

    function testUnbindToken() public {
        address user1 = vm.addr(1);

        uint256 tbtId = tbt.ownerMint(user1);
        uint256 mockTokenId = mockToken.mint(user1, 1);

        address contractAddress = address(mockToken);
        uint256 tokenId = mockTokenId;

        // successful bind for user 1
        vm.prank(user1);
        tbt.bind(contractAddress, tokenId, tbtId);

        bool bound1 = tbt.isBound(tbtId);
        assertEq(bound1, true);

        address tbtAddress = address(tbt);
        address tbtOwner = tbt.ownerOf(tbtId);
        assertEq(tbtOwner, tbtAddress);

        // unbind token
        vm.prank(user1);
        tbt.unbind(tbtId);

        bool bound2 = tbt.isBound(tbtId);
        assertEq(bound2, false);
        address tbtOwner2 = tbt.ownerOf(tbtId);
        assertEq(tbtOwner2, user1);
    }

    function testUnbindSoulboundTokenFail() public {
        address user1 = vm.addr(1);

        uint256 sbTbtId = sbTbt.ownerMint(user1);
        uint256 mockTokenId = mockToken.mint(user1, 1);

        address contractAddress = address(mockToken);
        uint256 tokenId = mockTokenId;

        // successful bind for user 1
        vm.prank(user1);
        sbTbt.bind(contractAddress, tokenId, sbTbtId);

        bool bound1 = sbTbt.isBound(sbTbtId);
        assertEq(bound1, true);

        address sbTbtAddress = address(sbTbt);
        address sbTbtOwner = sbTbt.ownerOf(sbTbtId);
        assertEq(sbTbtOwner, sbTbtAddress);

        // unbind token
        vm.prank(user1);

        vm.expectRevert("TBT: soulbound");
        sbTbt.unbind(sbTbtId);
    }
}
