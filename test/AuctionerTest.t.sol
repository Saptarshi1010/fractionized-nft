// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Auctioner} from "../src/Auctioner.sol";
import {Digitalizer} from "../src/Digitalizer.sol";
import {Fractionalizer} from "../src/Fractionalizer.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract AuctionerTest is Test {
    /// @dev Events
    event AuctionCreated(uint indexed id, address collection, uint tokenId, uint indexed nftFractionsAmount, uint indexed price);
    event Purchase(uint auction, address buyer, uint amount, uint available);
    event FundsTransferredToBroker(uint indexed auction, uint indexed amount);
    event AuctionStateChange(uint indexed auction, AuctionState indexed state);
    event AuctionOpened(uint indexed openTime, uint indexed closeTime);
    event AuctionRefund(address indexed buyer, uint indexed amount);

    /// @dev Enums
    enum AuctionState {
        UNSCHEDULED,
        SCHEDULED,
        OPEN, // auction ready to get orders for nft fractions
        CLOSED, // auction finished positively - all nft fractions bought
        FAILED, // auction finished negatively - not all nft fractions bought
        FINISHED, // UNUSED
        ARCHIVED
    }

    Auctioner public auctioner;
    Digitalizer public digitalizer;

    address private OWNER = makeAddr("owner");
    address private BROKER = makeAddr("broker");
    address private USER = makeAddr("user");
    address private USER_TWO = makeAddr("user_two");
    uint256 private constant STARTING_BALANCE = 100 ether;

    address private assoCoin = 0xf801f3A6F4e09F82D6008505C67a0A5b39842406;

    function setUp() public {
        deal(OWNER, STARTING_BALANCE);
        deal(USER, STARTING_BALANCE);
        deal(USER_TWO, STARTING_BALANCE);

        vm.startPrank(OWNER);
        auctioner = new Auctioner(payable(BROKER));

        digitalizer = new Digitalizer(address(auctioner), "Rolex", "RLX");

        auctioner.transferOwnership(address(digitalizer));

        digitalizer.safeMint();
        digitalizer.safeMint();
        vm.stopPrank();
    }

    function test_canInitializeAuction() public {
        vm.expectEmit(true, true, true, true, address(auctioner));
        emit AuctionCreated(0, address(digitalizer), 1, 100, 0.5 ether);
        vm.expectEmit(true, true, true, true, address(auctioner));
        emit AuctionStateChange(0, AuctionState.SCHEDULED);
        vm.prank(OWNER);
        digitalizer.initialize(1, 100, 0.5 ether);

        uint[] memory amt = auctioner.getReceivedTokens();

        assertEq(amt.length, 1);
        assertEq(amt[0], 1);
        assertEq(auctioner.s_totalAuctions(), 1);

        // address associatedCoin; // Address of associated erc20 contract
        IERC721 collection; // Address of nft that we want to fractionalize
        uint tokenId; // TokenId of NFT that we want to fractionalize
        uint closeTs; // Timestamp - auction close -> CAUTION we can safely remove openTs as time left will be sufficient
        uint openTs; // Timestamp - auction open
        uint available; // Amount of nft fractions left for sale
        uint total; // Total of nft fractions
        uint price; // Price of one nft fraction
        // uint payments; // Total ETH gathered
        // address[] memory tokenOwners; // NFT owners array
        Auctioner.AuctionState auctionState; // Auction status

        (, collection, tokenId, closeTs, openTs, available, total, price, , , auctionState) = auctioner.getAuctionData(0);

        assertEq(address(collection), address(digitalizer));
        assertEq(tokenId, 1);
        assertEq(closeTs, 0);
        assertEq(openTs, 0);
        assertEq(available, 100);
        assertEq(total, 100);
        assertEq(price, 0.5 ether);
        assert(auctionState == Auctioner.AuctionState.SCHEDULED);
    }

    function test_canOpenAuction() public {
        vm.expectRevert(Auctioner.Auctioner__AuctionDoesNotExists.selector);
        vm.prank(address(digitalizer));
        auctioner.open(0);

        vm.prank(OWNER);
        digitalizer.initialize(1, 100, 0.5 ether);

        vm.expectEmit(true, true, true, true, address(auctioner));
        emit AuctionOpened(block.timestamp, block.timestamp + 30 days);
        vm.expectEmit(true, true, true, true, address(auctioner));
        emit AuctionStateChange(0, AuctionState.OPEN);
        vm.prank(address(digitalizer));
        auctioner.open(0);

        uint closeTs; // Timestamp - auction close -> CAUTION we can safely remove openTs as time left will be sufficient
        uint openTs; // Timestamp - auction open
        Auctioner.AuctionState auctionState; // Auction status

        (, , , closeTs, openTs, , , , , , auctionState) = auctioner.getAuctionData(0);

        assertEq(closeTs, block.timestamp + 30 days);
        assertEq(openTs, block.timestamp);
        assert(auctionState == Auctioner.AuctionState.OPEN);
    }

    function test_canBuyFractionNFT() public {
        vm.prank(OWNER);
        digitalizer.initialize(1, 100, 0.5 ether);

        vm.prank(address(digitalizer));
        auctioner.open(0);

        vm.expectRevert(Auctioner.Auctioner__NotEnoughETH.selector);
        auctioner.buy(0, 3);

        vm.expectRevert(Auctioner.Auctioner__NotEnoughETH.selector);
        auctioner.buy{value: 1.49 ether}(0, 3);

        vm.expectEmit(true, true, true, true, address(auctioner));
        emit Purchase(0, USER, 3, 97);
        vm.prank(USER);
        auctioner.buy{value: 1.5 ether}(0, 3);

        vm.prank(USER);
        auctioner.buy{value: 0.5 ether}(0, 1);

        uint votes = Fractionalizer(assoCoin).getVotes(USER);

        assertEq(votes, 4);

        vm.expectEmit(true, true, true, true, address(auctioner));
        emit AuctionStateChange(0, AuctionState.CLOSED);
        vm.expectEmit(true, true, true, true, address(auctioner));
        emit FundsTransferredToBroker(0, 50 ether);
        vm.prank(USER_TWO);
        auctioner.buy{value: 48 ether}(0, 96);

        uint votes2 = Fractionalizer(assoCoin).getVotes(USER_TWO);

        assertEq(votes2, 96);
    }

    function test_canFailAuctionIfTimePassed() public {
        uint user_balance;
        uint user_two_balance;

        user_balance = USER.balance;
        user_two_balance = USER_TWO.balance;
        assertEq(user_balance, 100 ether);
        assertEq(user_two_balance, 100 ether);

        vm.prank(OWNER);
        digitalizer.initialize(1, 100, 0.5 ether);

        vm.prank(address(digitalizer));
        auctioner.open(0);

        vm.prank(USER);
        auctioner.buy{value: 1.5 ether}(0, 3);

        vm.warp(block.timestamp + 30 days + 1);
        vm.roll(block.number + 1);

        vm.expectEmit(true, true, true, true, address(auctioner));
        emit AuctionStateChange(0, AuctionState.FAILED);
        vm.expectEmit(true, true, true, true, address(auctioner));
        emit AuctionRefund(USER, 1.5 ether);
        vm.expectEmit(true, true, true, true, address(auctioner));
        emit AuctionRefund(USER_TWO, 20 ether);
        vm.expectEmit(true, true, true, true, address(auctioner));
        emit AuctionStateChange(0, AuctionState.ARCHIVED);
        vm.prank(USER_TWO);
        auctioner.buy{value: 20 ether}(0, 40);

        user_balance = USER.balance;
        user_two_balance = USER_TWO.balance;
        assertEq(user_balance, 100 ether);
        assertEq(user_two_balance, 100 ether);

        uint votes = Fractionalizer(assoCoin).getVotes(USER);
        uint votes2 = Fractionalizer(assoCoin).getVotes(USER_TWO);

        assertEq(votes, 0);
        assertEq(votes2, 0);
    }
}
