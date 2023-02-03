// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Libraries, interfaces, errors
import {SignatureParameterVInvalid, SignatureParameterSInvalid, SignatureEOAInvalid, NullSignerAddress, SignatureLengthInvalid} from "@looksrare/contracts-libs/contracts/errors/SignatureCheckerErrors.sol";
import {OrderStructs} from "../../contracts/libraries/OrderStructs.sol";

// Base test
import {ProtocolBase} from "./ProtocolBase.t.sol";

// Constants
import {ONE_HUNDRED_PERCENT_IN_BP, ASSET_TYPE_ERC721} from "../../contracts/constants/NumericConstants.sol";
import {INVALID_S_PARAMETER_EOA, INVALID_V_PARAMETER_EOA, NULL_SIGNER_EOA, INVALID_SIGNATURE_LENGTH, INVALID_SIGNER_EOA} from "../../contracts/constants/ValidationCodeConstants.sol";

contract SignaturesRevertionsTest is ProtocolBase {
    uint256 internal constant _MAX_PRIVATE_KEY =
        115792089237316195423570985008687907852837564279074904382605163141518161494337;

    function setUp() public {
        _setUp();
    }

    function testRevertIfSignatureEOAInvalid(uint256 itemId, uint256 price, uint256 randomPK) public {
        // @dev Private keys 1 and 2 are used for maker/taker users
        vm.assume(randomPK > 2 && randomPK < _MAX_PRIVATE_KEY);

        OrderStructs.MakerAsk memory makerAsk = _createSingleItemMakerAskOrder({
            askNonce: 0,
            subsetNonce: 0,
            strategyId: STANDARD_SALE_FOR_FIXED_PRICE_STRATEGY,
            assetType: ASSET_TYPE_ERC721,
            orderNonce: 0,
            collection: address(mockERC721),
            currency: ETH,
            signer: makerUser,
            minPrice: price,
            itemId: itemId
        });

        address randomUser = vm.addr(randomPK);
        _setUpUser(randomUser);
        bytes memory signature = _signMakerAsk(makerAsk, randomPK);
        _doesMakerAskOrderReturnValidationCode(makerAsk, signature, INVALID_SIGNER_EOA);

        OrderStructs.Taker memory takerBid = OrderStructs.Taker(takerUser, abi.encode());

        vm.expectRevert(SignatureEOAInvalid.selector);
        vm.prank(takerUser);
        looksRareProtocol.executeTakerBid(takerBid, makerAsk, signature, _EMPTY_MERKLE_TREE, _EMPTY_AFFILIATE);
    }

    function testRevertIfInvalidVParameter(uint256 itemId, uint256 price, uint8 v) public {
        vm.assume(v != 27 && v != 28);

        OrderStructs.MakerAsk memory makerAsk = _createSingleItemMakerAskOrder({
            askNonce: 0,
            subsetNonce: 0,
            strategyId: STANDARD_SALE_FOR_FIXED_PRICE_STRATEGY,
            assetType: ASSET_TYPE_ERC721,
            orderNonce: 0,
            collection: address(mockERC721),
            currency: ETH,
            signer: makerUser,
            minPrice: price,
            itemId: itemId
        });

        // Sign but replace v by the fuzzed v
        bytes32 orderHash = _computeOrderHashMakerAsk(makerAsk);
        (, bytes32 r, bytes32 s) = vm.sign(
            makerUserPK,
            keccak256(abi.encodePacked("\x19\x01", _domainSeparator, orderHash))
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        _doesMakerAskOrderReturnValidationCode(makerAsk, signature, INVALID_V_PARAMETER_EOA);

        OrderStructs.Taker memory takerBid = OrderStructs.Taker(takerUser, abi.encode());

        vm.expectRevert(abi.encodeWithSelector(SignatureParameterVInvalid.selector, v));
        vm.prank(takerUser);
        looksRareProtocol.executeTakerBid(takerBid, makerAsk, signature, _EMPTY_MERKLE_TREE, _EMPTY_AFFILIATE);
    }

    function testRevertIfInvalidSParameter(uint256 itemId, uint256 price, bytes32 s) public {
        vm.assume(uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0);

        OrderStructs.MakerAsk memory makerAsk = _createSingleItemMakerAskOrder({
            askNonce: 0,
            subsetNonce: 0,
            strategyId: STANDARD_SALE_FOR_FIXED_PRICE_STRATEGY,
            assetType: ASSET_TYPE_ERC721,
            orderNonce: 0,
            collection: address(mockERC721),
            currency: ETH,
            signer: makerUser,
            minPrice: price,
            itemId: itemId
        });

        // Sign but replace s by the fuzzed s
        bytes32 orderHash = _computeOrderHashMakerAsk(makerAsk);
        (uint8 v, bytes32 r, ) = vm.sign(
            makerUserPK,
            keccak256(abi.encodePacked("\x19\x01", _domainSeparator, orderHash))
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        _doesMakerAskOrderReturnValidationCode(makerAsk, signature, INVALID_S_PARAMETER_EOA);

        OrderStructs.Taker memory takerBid = OrderStructs.Taker(takerUser, abi.encode());

        vm.expectRevert(abi.encodeWithSelector(SignatureParameterSInvalid.selector));
        vm.prank(takerUser);
        looksRareProtocol.executeTakerBid(takerBid, makerAsk, signature, _EMPTY_MERKLE_TREE, _EMPTY_AFFILIATE);
    }

    function testRevertIfRecoveredSignerIsNullAddress(uint256 itemId, uint256 price) public {
        OrderStructs.MakerAsk memory makerAsk = _createSingleItemMakerAskOrder({
            askNonce: 0,
            subsetNonce: 0,
            strategyId: STANDARD_SALE_FOR_FIXED_PRICE_STRATEGY,
            assetType: ASSET_TYPE_ERC721,
            orderNonce: 0,
            collection: address(mockERC721),
            currency: ETH,
            signer: makerUser,
            minPrice: price,
            itemId: itemId
        });

        // Sign but replace r by empty bytes32
        bytes32 orderHash = _computeOrderHashMakerAsk(makerAsk);
        (uint8 v, , bytes32 s) = vm.sign(
            makerUserPK,
            keccak256(abi.encodePacked("\x19\x01", _domainSeparator, orderHash))
        );

        bytes32 r;
        bytes memory signature = abi.encodePacked(r, s, v);

        _doesMakerAskOrderReturnValidationCode(makerAsk, signature, NULL_SIGNER_EOA);

        OrderStructs.Taker memory takerBid = OrderStructs.Taker(takerUser, abi.encode());

        vm.expectRevert(abi.encodeWithSelector(NullSignerAddress.selector));
        vm.prank(takerUser);
        looksRareProtocol.executeTakerBid(takerBid, makerAsk, signature, _EMPTY_MERKLE_TREE, _EMPTY_AFFILIATE);
    }

    function testRevertIfInvalidSignatureLength(uint256 itemId, uint256 price, uint256 length) public {
        // @dev Getting OutOfGas starting from 16,776,985, probably due to memory cost
        vm.assume(length != 64 && length != 65 && length < 16_776_985);

        OrderStructs.MakerAsk memory makerAsk = _createSingleItemMakerAskOrder({
            askNonce: 0,
            subsetNonce: 0,
            strategyId: STANDARD_SALE_FOR_FIXED_PRICE_STRATEGY,
            assetType: ASSET_TYPE_ERC721,
            orderNonce: 0,
            collection: address(mockERC721),
            currency: ETH,
            signer: makerUser,
            minPrice: price,
            itemId: itemId
        });

        bytes memory signature = new bytes(length);
        _doesMakerAskOrderReturnValidationCode(makerAsk, signature, INVALID_SIGNATURE_LENGTH);

        OrderStructs.Taker memory takerBid = OrderStructs.Taker(takerUser, abi.encode());

        vm.expectRevert(abi.encodeWithSelector(SignatureLengthInvalid.selector, length));
        vm.prank(takerUser);
        looksRareProtocol.executeTakerBid(takerBid, makerAsk, signature, _EMPTY_MERKLE_TREE, _EMPTY_AFFILIATE);
    }
}