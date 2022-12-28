// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Libraries
import {OrderStructs} from "../libraries/OrderStructs.sol";

// Shared errors
import {OrderInvalid} from "../interfaces/SharedErrors.sol";

/**
 * @title StrategyItemIdsRange
 * @author LooksRare protocol team (👀,💎)
 */
contract StrategyItemIdsRange {
    /**
     * @notice Validate the order under the context of the chosen strategy and return the fulfillable items/amounts/price/nonce invalidation status
     *         Bidder picks a item id range (e.g. 1-100) and a seller can fulfill the order with any tokens within the specificed ID range
     * @param takerAsk Taker ask struct (contains the taker ask-specific parameters for the execution of the transaction)
     * @param makerBid Maker bid struct (contains the maker bid-specific parameters for the execution of the transaction)
     */
    function executeStrategyWithTakerAsk(
        OrderStructs.TakerAsk calldata takerAsk,
        OrderStructs.MakerBid calldata makerBid
    )
        external
        pure
        returns (uint256 price, uint256[] memory itemIds, uint256[] memory amounts, bool isNonceInvalidated)
    {
        uint256 minItemId = makerBid.itemIds[0];
        uint256 maxItemId = makerBid.itemIds[1];

        if (minItemId >= maxItemId) {
            revert OrderInvalid();
        }

        uint256 desiredAmount = makerBid.amounts[0];
        uint256 totalOfferedAmount;
        uint256 lastItemId;
        uint256 length = takerAsk.itemIds.length;

        for (uint256 i; i < length; ) {
            uint256 offeredItemId = takerAsk.itemIds[i];
            // Force the client to sort the item ids in ascending order,
            // in order to prevent taker ask from providing duplicated
            // item ids
            if (offeredItemId <= lastItemId && i != 0) {
                revert OrderInvalid();
            }

            // If ERC721, force amount to be 1.
            uint256 offeredAmount = makerBid.assetType == 0 ? 1 : takerAsk.amounts[i];
            if (offeredAmount == 0) {
                revert OrderInvalid();
            }

            if (offeredItemId >= minItemId) {
                if (offeredItemId <= maxItemId) {
                    totalOfferedAmount += offeredAmount;
                }
            }

            lastItemId = offeredItemId;

            unchecked {
                ++i;
            }
        }

        if (totalOfferedAmount != desiredAmount) {
            revert OrderInvalid();
        }

        if (makerBid.maxPrice != takerAsk.minPrice) {
            revert OrderInvalid();
        }

        price = makerBid.maxPrice;
        itemIds = takerAsk.itemIds;
        amounts = takerAsk.amounts;
        isNonceInvalidated = true;
    }

    /**
     * @notice Validate *only the maker* order under the context of the chosen strategy. It does not revert if
     *         the maker order is invalid. Instead it returns false and the error's 4 bytes selector.
     * @param makerBid Maker bid struct (contains the maker bid-specific parameters for the execution of the transaction)
     * @return orderIsValid Whether the maker struct is valid
     * @return errorSelector If isValid is false, return the error's 4 bytes selector
     */
    function isValid(
        OrderStructs.MakerBid calldata makerBid
    ) external pure returns (bool orderIsValid, bytes4 errorSelector) {
        uint256 minItemId = makerBid.itemIds[0];
        uint256 maxItemId = makerBid.itemIds[1];
        if (minItemId >= maxItemId) {
            return (orderIsValid, OrderInvalid.selector);
        }

        orderIsValid = true;
    }
}