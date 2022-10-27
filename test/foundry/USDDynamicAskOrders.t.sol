// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderStructs} from "../../contracts/libraries/OrderStructs.sol";
import {IExecutionStrategy} from "../../contracts/interfaces/IExecutionStrategy.sol";
import {IStrategyManager} from "../../contracts/interfaces/IStrategyManager.sol";
import {StrategyUSDDynamicAsk} from "../../contracts/executionStrategies/StrategyUSDDynamicAsk.sol";
import {StrategyChainlinkPriceLatency} from "../../contracts/executionStrategies/StrategyChainlinkPriceLatency.sol";
import {ProtocolBase} from "./ProtocolBase.t.sol";
import {ChainlinkMaximumLatencyTest} from "./ChainlinkMaximumLatency.t.sol";

contract USDDynamicAskOrdersTest is ProtocolBase, IStrategyManager, ChainlinkMaximumLatencyTest {
    string private constant MAINNET_RPC_URL = "https://rpc.ankr.com/eth";
    StrategyUSDDynamicAsk public strategy;
    // At block 15740567
    // roundId         uint80  :  92233720368547793259
    // answer          int256  :  126533075631
    // startedAt       uint256 :  1665680123
    // updatedAt       uint256 :  1665680123
    // answeredInRound uint80  :  92233720368547793259
    uint256 private constant FORKED_BLOCK_NUMBER = 15740567;
    uint256 private constant LATEST_CHAINLINK_ANSWER_IN_WAD = 126533075631 * 1e10;

    function setUp() public override {
        vm.createSelectFork(MAINNET_RPC_URL, FORKED_BLOCK_NUMBER);
        super.setUp();

        _setUpUsers();
        _setUpNewStrategy();
        _setUpRoyalties(address(mockERC721), _standardRoyaltyFee);
    }

    function _setUpNewStrategy() private asPrankedUser(_owner) {
        strategy = new StrategyUSDDynamicAsk(address(looksRareProtocol));
        looksRareProtocol.addStrategy(true, _standardProtocolFee, 300, address(strategy));
    }

    function _createMakerAskAndTakerBid(
        uint256 numberOfItems,
        uint256 numberOfAmounts,
        uint256 desiredSalePriceInUSD
    ) private returns (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) {
        uint256[] memory itemIds = new uint256[](numberOfItems);
        for (uint256 i; i < numberOfItems; ) {
            mockERC721.mint(makerUser, i + 1);
            itemIds[i] = i + 1;
            unchecked {
                ++i;
            }
        }

        uint256[] memory amounts = new uint256[](numberOfAmounts);
        for (uint256 i; i < numberOfAmounts; ) {
            amounts[i] = 1;
            unchecked {
                ++i;
            }
        }

        uint16 minNetRatio = 10000 - (_standardRoyaltyFee + _standardProtocolFee); // 3% slippage protection

        // Prepare the order hash
        makerAsk = _createSingleItemMakerAskOrder({
            askNonce: 0,
            subsetNonce: 0,
            strategyId: 2,
            assetType: 0,
            orderNonce: 0,
            minNetRatio: minNetRatio,
            collection: address(mockERC721),
            currency: address(weth),
            signer: makerUser,
            minPrice: 0.99 ether,
            itemId: 1
        });

        makerAsk.itemIds = itemIds;
        makerAsk.amounts = amounts;

        makerAsk.additionalParameters = abi.encode(desiredSalePriceInUSD);

        takerBid = OrderStructs.TakerBid({
            recipient: takerUser,
            minNetRatio: makerAsk.minNetRatio,
            maxPrice: 1 ether,
            itemIds: itemIds,
            amounts: amounts,
            additionalParameters: abi.encode()
        });
    }

    function testNewStrategy() public {
        Strategy memory newStrategy = looksRareProtocol.strategyInfo(2);
        assertTrue(newStrategy.isActive);
        assertTrue(newStrategy.hasRoyalties);
        assertEq(newStrategy.protocolFee, _standardProtocolFee);
        assertEq(newStrategy.maxProtocolFee, uint16(300));
        assertEq(newStrategy.implementation, address(strategy));
    }

    function testSetMaximumLatency() public {
        _testSetMaximumLatency(looksRareProtocol.strategyInfo(2).implementation);
    }

    function testSetMaximumLatencyLatencyToleranceTooHigh() public {
        _testSetMaximumLatencyLatencyToleranceTooHigh(looksRareProtocol.strategyInfo(2).implementation);
    }

    function testSetMaximumLatencyNotOwner() public {
        _testSetMaximumLatencyNotOwner(looksRareProtocol.strategyInfo(2).implementation);
    }

    function testUSDDynamicAskUSDValueGreaterThanOrEqualToMinAcceptedEthValue() public {
        strategy = StrategyUSDDynamicAsk(looksRareProtocol.strategyInfo(2).implementation);

        (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) = _createMakerAskAndTakerBid({
            numberOfItems: 1,
            numberOfAmounts: 1,
            desiredSalePriceInUSD: LATEST_CHAINLINK_ANSWER_IN_WAD
        });

        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.prank(_owner);
        strategy.setMaximumLatency(3600);

        vm.prank(takerUser);
        // Execute taker bid transaction
        looksRareProtocol.executeTakerBid(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        // Taker user has received the asset
        assertEq(mockERC721.ownerOf(1), takerUser);

        // Taker bid user pays the whole price
        assertEq(weth.balanceOf(takerUser), _initialWETHBalanceUser - 1 ether);
        // Maker ask user receives 97% of the whole price (2% protocol + 1% royalties)
        assertEq(weth.balanceOf(makerUser), _initialWETHBalanceUser + 0.97 ether);
    }

    function testUSDDynamicAskUSDValueLessThanMinAcceptedEthValue() public {
        strategy = StrategyUSDDynamicAsk(looksRareProtocol.strategyInfo(2).implementation);

        (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) = _createMakerAskAndTakerBid({
            numberOfItems: 1,
            numberOfAmounts: 1,
            desiredSalePriceInUSD: (LATEST_CHAINLINK_ANSWER_IN_WAD * 98) / 100
        });

        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.prank(_owner);
        strategy.setMaximumLatency(3600);

        vm.prank(takerUser);
        // Execute taker bid transaction
        looksRareProtocol.executeTakerBid(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        // Taker user has received the asset
        assertEq(mockERC721.ownerOf(1), takerUser);

        // Taker bid user pays the whole price
        assertEq(weth.balanceOf(takerUser), _initialWETHBalanceUser - 0.99 ether);
        // Maker ask user receives 97% of the whole price (2% protocol + 1% royalties)
        assertEq(weth.balanceOf(makerUser), _initialWETHBalanceUser + 0.9603 ether);
    }

    // This tests that we can handle fractions
    function testUSDDynamicAskUSDValueLessThanOneETH() public {
        strategy = StrategyUSDDynamicAsk(looksRareProtocol.strategyInfo(2).implementation);

        (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) = _createMakerAskAndTakerBid({
            numberOfItems: 1,
            numberOfAmounts: 1,
            desiredSalePriceInUSD: LATEST_CHAINLINK_ANSWER_IN_WAD / 2
        });

        makerAsk.minPrice = 0.49 ether;

        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.prank(_owner);
        strategy.setMaximumLatency(3600);

        vm.prank(takerUser);
        // Execute taker bid transaction
        looksRareProtocol.executeTakerBid(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        // Taker user has received the asset
        assertEq(mockERC721.ownerOf(1), takerUser);

        // Taker bid user pays the whole price
        assertEq(weth.balanceOf(takerUser), _initialWETHBalanceUser - 0.5 ether);
        // Maker ask user receives 97% of the whole price (2% protocol + 1% royalties)
        assertEq(weth.balanceOf(makerUser), _initialWETHBalanceUser + 0.485 ether);
    }

    function testUSDDynamicAskBidderOverpaid() public {
        strategy = StrategyUSDDynamicAsk(looksRareProtocol.strategyInfo(2).implementation);

        (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) = _createMakerAskAndTakerBid({
            numberOfItems: 1,
            numberOfAmounts: 1,
            desiredSalePriceInUSD: LATEST_CHAINLINK_ANSWER_IN_WAD
        });

        // Make the order currency native ETH
        makerAsk.currency = address(0);
        // Bidder overpays by 0.1 ETH
        takerBid.maxPrice = 1.1 ether;

        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.prank(_owner);
        strategy.setMaximumLatency(3600);

        uint256 initialETHBalanceTakerUser = address(takerUser).balance;
        uint256 initialETHBalanceMakerUser = address(makerUser).balance;

        vm.prank(takerUser);
        // Execute taker bid transaction
        looksRareProtocol.executeTakerBid{value: takerBid.maxPrice}(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        // Taker user has received the asset
        assertEq(mockERC721.ownerOf(1), takerUser);

        // Taker bid user pays the whole price, but without overpaying
        assertEq(address(takerUser).balance, initialETHBalanceTakerUser - 1 ether);
        // Maker ask user receives 97% of the whole price (2% protocol + 1% royalties)
        assertEq(address(makerUser).balance, initialETHBalanceMakerUser + 0.97 ether);
    }

    function testOraclePriceNotRecentEnough() public {
        strategy = StrategyUSDDynamicAsk(looksRareProtocol.strategyInfo(2).implementation);

        (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) = _createMakerAskAndTakerBid({
            numberOfItems: 1,
            numberOfAmounts: 1,
            desiredSalePriceInUSD: LATEST_CHAINLINK_ANSWER_IN_WAD
        });

        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.expectRevert(StrategyChainlinkPriceLatency.PriceNotRecentEnough.selector);
        vm.prank(takerUser);
        // Execute taker bid transaction
        looksRareProtocol.executeTakerBid(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );
    }

    function testCallerNotLooksRareProtocol() public {
        strategy = StrategyUSDDynamicAsk(looksRareProtocol.strategyInfo(2).implementation);

        (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) = _createMakerAskAndTakerBid({
            numberOfItems: 1,
            numberOfAmounts: 1,
            desiredSalePriceInUSD: LATEST_CHAINLINK_ANSWER_IN_WAD
        });

        vm.expectRevert(IExecutionStrategy.WrongCaller.selector);
        // Call the function directly
        strategy.executeStrategyWithTakerBid(takerBid, makerAsk);
    }

    function testZeroItemIdsLength() public {
        strategy = StrategyUSDDynamicAsk(looksRareProtocol.strategyInfo(2).implementation);

        (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) = _createMakerAskAndTakerBid({
            numberOfItems: 0,
            numberOfAmounts: 0,
            desiredSalePriceInUSD: LATEST_CHAINLINK_ANSWER_IN_WAD
        });

        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.prank(_owner);
        strategy.setMaximumLatency(3600);

        vm.expectRevert(IExecutionStrategy.OrderInvalid.selector);
        vm.prank(takerUser);
        // Execute taker bid transaction
        looksRareProtocol.executeTakerBid(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );
    }

    function testItemIdsAndAmountsLengthMismatch() public {
        strategy = StrategyUSDDynamicAsk(looksRareProtocol.strategyInfo(2).implementation);

        (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) = _createMakerAskAndTakerBid({
            numberOfItems: 1,
            numberOfAmounts: 2,
            desiredSalePriceInUSD: LATEST_CHAINLINK_ANSWER_IN_WAD
        });

        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.prank(_owner);
        strategy.setMaximumLatency(3600);

        vm.expectRevert(IExecutionStrategy.OrderInvalid.selector);
        vm.prank(takerUser);
        // Execute taker bid transaction
        looksRareProtocol.executeTakerBid(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );
    }

    function testItemIdsMismatch() public {
        strategy = StrategyUSDDynamicAsk(looksRareProtocol.strategyInfo(2).implementation);

        (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) = _createMakerAskAndTakerBid({
            numberOfItems: 1,
            numberOfAmounts: 1,
            desiredSalePriceInUSD: LATEST_CHAINLINK_ANSWER_IN_WAD
        });

        uint256[] memory itemIds = new uint256[](1);
        itemIds[0] = 2;

        // Bidder bidding on something else
        takerBid.itemIds = itemIds;

        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.prank(_owner);
        strategy.setMaximumLatency(3600);

        vm.expectRevert(IExecutionStrategy.OrderInvalid.selector);
        vm.prank(takerUser);
        // Execute taker bid transaction
        looksRareProtocol.executeTakerBid(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );
    }

    function testZeroAmount() public {
        strategy = StrategyUSDDynamicAsk(looksRareProtocol.strategyInfo(2).implementation);

        (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) = _createMakerAskAndTakerBid({
            numberOfItems: 1,
            numberOfAmounts: 1,
            desiredSalePriceInUSD: LATEST_CHAINLINK_ANSWER_IN_WAD
        });

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        makerAsk.amounts = amounts;

        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.prank(_owner);
        strategy.setMaximumLatency(3600);

        vm.expectRevert(IExecutionStrategy.OrderInvalid.selector);
        vm.prank(takerUser);
        // Execute taker bid transaction
        looksRareProtocol.executeTakerBid(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );
    }

    function testTakerBidTooLow() public {
        strategy = StrategyUSDDynamicAsk(looksRareProtocol.strategyInfo(2).implementation);

        (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) = _createMakerAskAndTakerBid({
            numberOfItems: 1,
            numberOfAmounts: 1,
            desiredSalePriceInUSD: LATEST_CHAINLINK_ANSWER_IN_WAD
        });

        takerBid.maxPrice = 0.99 ether;

        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.prank(_owner);
        strategy.setMaximumLatency(3600);

        vm.expectRevert(IExecutionStrategy.BidTooLow.selector);
        vm.prank(takerUser);
        // Execute taker bid transaction
        looksRareProtocol.executeTakerBid(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );
    }
}