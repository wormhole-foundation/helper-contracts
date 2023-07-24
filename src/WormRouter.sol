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
        if(additionalVaas.length == 0) {
            bytes memory data;
            (targetAddress, data) = abi.decode(payload, (address, bytes));
            (success,) = targetAddress.call{value: msg.value}(data);
        } else if(additionalVaas.length == 1) {
            bytes4 selector;
            (selector, targetAddress) = abi.decode(payload, (bytes4, address));
            (success,) = targetAddress.call{value: msg.value}(abi.encodeWithSelector(selector, additionalVaas[0]));
        }

        emit CrossChainAction(sourceChain, sourceAddress, targetAddress, success);
    }
}