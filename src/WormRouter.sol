// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";

contract WormRouter is IWormholeReceiver {

    IWormholeRelayer immutable wormholeRelayer;

    event CrossChainAction(uint16 sourceChain, bytes32 sourceAddress, address targetAddress, bool success);

    constructor(address _wormholeRelayer) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
    }

    enum Version {ARBITRARY_CALL_DATA, ONE_VAA}

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress, // address that called 'sendPayloadToEvm' (HelloWormhole contract address)
        uint16 sourceChain,
        bytes32 // deliveryHash - this can be stored in a mapping deliveryHash => bool to prevent duplicate deliveries
    ) public payable override {
        require(msg.sender == address(wormholeRelayer), "Only relayer allowed");
        address targetAddress;
        bool success = false;

        Version version = abi.decode(payload, (Version));
        if(version == Version.ARBITRARY_CALL_DATA) {
            bytes memory data;
            (,targetAddress, data) = abi.decode(payload, (Version, address, bytes));
            (success,) = targetAddress.call{value: msg.value}(data);
        } else if(version == Version.ONE_VAA) {
            bytes4 selector;
            (,selector, targetAddress) = abi.decode(payload, (Version, bytes4, address));
            (success,) = targetAddress.call{value: msg.value}(abi.encodeWithSelector(selector, additionalVaas[0]));
        }

        emit CrossChainAction(sourceChain, sourceAddress, targetAddress, success);
    }
}