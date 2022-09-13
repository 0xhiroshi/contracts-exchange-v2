// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IExecutionManager} from "../../contracts/interfaces/IExecutionManager.sol";
import {OrderStructs} from "../../contracts/libraries/OrderStructs.sol";
import {ProtocolBase} from "./ProtocolBase.t.sol";

contract ExecutionManagerTest is ProtocolBase, IExecutionManager {
    /**
    /**
     * Owner can change protocol fee and deactivate royalty
     */
    function testOwnerCanChangeStrategyProtocolFeeAndDeactivateRoyalty() public asPrankedUser(_owner) {
        uint16 strategyId = 0;
        bool hasRoyalties = false;
        uint16 protocolFee = 250;
        bool isActive = true;

        vm.expectEmit(false, false, false, false);
        emit StrategyUpdated(strategyId, isActive, hasRoyalties, protocolFee);
        looksRareProtocol.updateStrategy(strategyId, hasRoyalties, protocolFee, isActive);

        Strategy memory strategy = looksRareProtocol.viewStrategy(strategyId);
        assertTrue(strategy.isActive);
        assertFalse(strategy.hasRoyalties);
        assertEq(strategy.protocolFee, protocolFee);
        assertEq(strategy.implementation, address(0));
    }

    /**
     * Owner can discontinue strategy
     */
    function testOwnerCanDiscontinueStrategy() public asPrankedUser(_owner) {
        uint16 strategyId = 1;
        bool hasRoyalties = true;
        uint16 protocolFee = 299;
        bool isActive = false;

        vm.expectEmit(false, false, false, false);
        emit StrategyUpdated(strategyId, isActive, hasRoyalties, protocolFee);
        looksRareProtocol.updateStrategy(strategyId, hasRoyalties, protocolFee, isActive);

        Strategy memory strategy = looksRareProtocol.viewStrategy(strategyId);
        assertFalse(strategy.isActive);
        assertTrue(strategy.hasRoyalties);
        assertEq(strategy.protocolFee, protocolFee);
        assertEq(strategy.implementation, address(0));
    }

    /**
     * Owner functions for strategy additions/updates revert as expected under multiple cases
     */
    function testOwnerRevertionsForWrongParametersAddStrategy() public asPrankedUser(_owner) {
        bool hasRoyalties = true;
        uint16 protocolFee = 250;
        uint16 maxProtocolFee = 300;
        address implementation = address(0);

        // 1. Strategy does not exist but maxProtocolFee is lower than protocolFee
        maxProtocolFee = protocolFee - 1;
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.StrategyProtocolFeeTooHigh.selector));
        looksRareProtocol.addStrategy(hasRoyalties, protocolFee, maxProtocolFee, implementation);

        // 2. Strategy does not exist but maxProtocolFee is higher than _MAX_PROTOCOL_FEE
        maxProtocolFee = 5000 + 1;
        vm.expectRevert(abi.encodeWithSelector(IExecutionManager.StrategyProtocolFeeTooHigh.selector));
        looksRareProtocol.addStrategy(hasRoyalties, protocolFee, maxProtocolFee, implementation);
    }

    function testCannotValidateOrderIfWrongTimestamps() public asPrankedUser(takerUser) {
        // Change timestamp to avoid underflow issues
        vm.warp(12000000);

        /**
         * 1. Too early to execute
         */
        (OrderStructs.MakerBid memory makerBid, OrderStructs.TakerAsk memory takerAsk) = _createMockMakerBidAndTakerAsk(
            address(mockERC721),
            address(weth)
        );

        makerBid.startTime = block.timestamp + 1;
        signature = _signMakerBid(makerBid, makerUserPK);

        vm.expectRevert(OutsideOfTimeRange.selector);
        looksRareProtocol.executeTakerAsk(
            takerAsk,
            makerBid,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        /**
         * 2. Too late to execute
         */
        makerBid.startTime = 0;
        makerBid.endTime = block.timestamp - 1;
        signature = _signMakerBid(makerBid, makerUserPK);

        vm.expectRevert(OutsideOfTimeRange.selector);
        looksRareProtocol.executeTakerAsk(
            takerAsk,
            makerBid,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );
    }

    function testCannotValidateOrderIfWrongFormat() public asPrankedUser(takerUser) {
        // (For takerBid tests)
        vm.deal(takerUser, 100 ether);

        /**
         * 1. COLLECTION STRATEGY: itemIds' length is greater than 1
         */
        (OrderStructs.MakerBid memory makerBid, OrderStructs.TakerAsk memory takerAsk) = _createMockMakerBidAndTakerAsk(
            address(mockERC721),
            address(weth)
        );

        // Adjust strategy for collection order and sign order
        // Change array to make it bigger than expected
        uint256[] memory itemIds = new uint256[](2);
        itemIds[0] = 0;
        makerBid.strategyId = 1;
        makerBid.itemIds = itemIds;
        takerAsk.itemIds = itemIds;
        signature = _signMakerBid(makerBid, makerUserPK);

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerAsk(
            takerAsk,
            makerBid,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        /**
         * 2. STANDARD STRATEGY/MAKER BID: itemIds' length is equal to 0
         */
        (makerBid, takerAsk) = _createMockMakerBidAndTakerAsk(address(mockERC721), address(weth));

        // Change makerBid itemIds array's length to make it equal to 0
        itemIds = new uint256[](0);
        makerBid.itemIds = itemIds;
        signature = _signMakerBid(makerBid, makerUserPK);

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerAsk(
            takerAsk,
            makerBid,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        /**
         * 3. STANDARD STRATEGY/MAKER BID: maker itemIds' length is not equal to maker amounts' length
         */
        (makerBid, takerAsk) = _createMockMakerBidAndTakerAsk(address(mockERC721), address(weth));

        // Change itemIds array for maker to make its length equal to 2
        itemIds = new uint256[](2);
        makerBid.itemIds = itemIds;
        signature = _signMakerBid(makerBid, makerUserPK);

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerAsk(
            takerAsk,
            makerBid,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        /**
         * 4. STANDARD STRATEGY/MAKER BID: itemIds' length of maker is not equal to length of taker
         */
        (makerBid, takerAsk) = _createMockMakerBidAndTakerAsk(address(mockERC721), address(weth));

        // Change itemIds array for taker to make its length equal to 2
        itemIds = new uint256[](2);
        takerAsk.itemIds = itemIds;
        signature = _signMakerBid(makerBid, makerUserPK);

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerAsk(
            takerAsk,
            makerBid,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        /**
         * 5. STANDARD STRATEGY/MAKER BID: amounts' length of maker is not equal to length of taker
         */
        (makerBid, takerAsk) = _createMockMakerBidAndTakerAsk(address(mockERC721), address(weth));

        // Change amounts array for taker to make its length equal to 2
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        takerAsk.amounts = amounts;
        signature = _signMakerBid(makerBid, makerUserPK);

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerAsk(
            takerAsk,
            makerBid,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        /**
         * 6. STANDARD STRATEGY/MAKER BID: maxPrice of maker is not equal to minPrice of taker
         */
        (makerBid, takerAsk) = _createMockMakerBidAndTakerAsk(address(mockERC721), address(weth));
        signature = _signMakerBid(makerBid, makerUserPK);

        // Change price of takerAsk to be higher than makerAsk price
        takerAsk.minPrice = makerBid.maxPrice + 1;

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerAsk(
            takerAsk,
            makerBid,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        // Change price of takerAsk to be higher than makerAsk price
        takerAsk.minPrice = makerBid.maxPrice - 1;

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerAsk(
            takerAsk,
            makerBid,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        /**
         * 7. STANDARD STRATEGY/MAKER ASK: itemIds' length of maker is equal to 0
         */
        (OrderStructs.MakerAsk memory makerAsk, OrderStructs.TakerBid memory takerBid) = _createMockMakerAskAndTakerBid(
            address(mockERC721)
        );

        // Change maker itemIds array to make its length equal to 0
        itemIds = new uint256[](0);
        makerAsk.itemIds = itemIds;
        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerBid{value: takerBid.maxPrice}(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        /**
         * 8. STANDARD STRATEGY/MAKER ASK: maker itemIds' length is not equal to maker amounts' length
         */
        (makerAsk, takerBid) = _createMockMakerAskAndTakerBid(address(mockERC721));

        // Change itemIds array to make it equal to 2
        itemIds = new uint256[](2);
        makerAsk.itemIds = itemIds;
        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerBid{value: takerBid.maxPrice}(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        /**
         * 9. STANDARD STRATEGY/MAKER ASK: itemIds' length of maker is not equal to length of taker
         */
        (makerAsk, takerBid) = _createMockMakerAskAndTakerBid(address(mockERC721));

        // Change itemIds array to make it equal to 2
        itemIds = new uint256[](2);
        takerBid.itemIds = itemIds;
        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerBid{value: takerBid.maxPrice}(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        /**
         * 10. STANDARD STRATEGY/MAKER ASK: amounts' length of maker is not equal to length of taker
         */

        // Change amounts array' length to make it equal to 2
        (makerAsk, takerBid) = _createMockMakerAskAndTakerBid(address(mockERC721));
        amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        takerBid.amounts = amounts;
        signature = _signMakerAsk(makerAsk, makerUserPK);

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerBid{value: takerBid.maxPrice}(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        /**
         * 11. STANDARD STRATEGY/MAKER ASK: minPrice of maker is not equal to maxPrice of taker
         */
        (makerAsk, takerBid) = _createMockMakerAskAndTakerBid(address(mockERC721));
        signature = _signMakerAsk(makerAsk, makerUserPK);

        // Change price of takerBid to be lower than makerAsk price
        takerBid.maxPrice = makerAsk.minPrice - 1;

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerBid{value: takerBid.maxPrice}(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );

        // Change price of takerBid to be higher than makerAsk price
        takerBid.maxPrice = makerAsk.minPrice + 1;

        vm.expectRevert(OrderInvalid.selector);
        looksRareProtocol.executeTakerBid{value: takerBid.maxPrice}(
            takerBid,
            makerAsk,
            signature,
            _emptyMerkleRoot,
            _emptyMerkleProof,
            _emptyReferrer
        );
    }
}