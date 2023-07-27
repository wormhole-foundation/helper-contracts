// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";

enum Version {
    ARBITRARY_CALL_DATA,
    ONE_VAA
}

contract WormRouter is IWormholeReceiver {
    event CrossChainAction(
        uint16 sourceChain, bytes32 sourceAddress, address targetAddress, bool success, bytes returnData
    );

    IWormholeRelayer public immutable wormholeRelayer;
    uint16 public immutable chainId;

    address owner;
    mapping(uint16 => address) wormRouters;

    constructor(address _wormholeRelayer, uint16 _chainId) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        chainId = _chainId;
        owner = msg.sender;
    }

    /**
     * Automatic Relayer endpoint - allowing users to request automatic relays
     * to contracts, without necessarily calling a 'receiveWormholeMessages' endpoint
     *
     * The endpoint to be called can be either an arbitrary one with arbitrary calldata specified on the source chain (Version.ARBITRARY_CALL_DATA)
     *
     * or, if a VAA is desired to be relayed, can be an arbitrary selector with exactly one 'bytes' argument - the signed VAA
     */

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress, // address that called 'sendPayloadToEvm' (either user or WormRouter)
        uint16 sourceChain,
        bytes32 // deliveryHash - this can be stored in a mapping deliveryHash => bool to prevent duplicate deliveries
    ) public payable override {
        require(msg.sender == address(wormholeRelayer));

        address targetAddress;
        bool success = false;
        bytes memory returnData;

        Version version = abi.decode(payload, (Version));
        if (version == Version.ARBITRARY_CALL_DATA) {
            bytes memory data;
            (, targetAddress, data) = abi.decode(payload, (Version, address, bytes));
            (success, returnData) = targetAddress.call{value: msg.value}(data);
        } else if (version == Version.ONE_VAA) {
            bytes4 selector;
            (, targetAddress, selector) = abi.decode(payload, (Version, address, bytes4));
            (success, returnData) =
                targetAddress.call{value: msg.value}(abi.encodeWithSelector(selector, additionalVaas[0]));
        }

        emit CrossChainAction(sourceChain, sourceAddress, targetAddress, success, returnData);
    }
}
