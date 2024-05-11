// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "wormhole-solidity-sdk/contracts/interfaces/IWormholeRelayer.sol";
import "wormhole-solidity-sdk/contracts/interfaces/IWormholeReceiver.sol";

enum ExecutionType {
    ArbitraryCallData,
    SingleVAA
}

contract WormRouter is IWormholeReceiver, Ownable {
    // Event names should be expressive.
    event CrossChainActionCompleted(
        uint16 indexed sourceChain,
        bytes32 indexed sourceAddress,
        address indexed targetAddress,
        bool success,
        bytes returnData
    );

    IWormholeRelayer public immutable wormholeRelayer;
    uint16 public immutable localChainId;

    constructor(address wormholeRelayerAddress, uint16 _localChainId) {
        require(wormholeRelayerAddress != address(0), "WormholeRelayer address cannot be zero");
        require(_localChainId != 0, "Chain ID cannot be zero");

        wormholeRelayer = IWormholeRelayer(wormholeRelayerAddress);
        localChainId = _localChainId;
    }

    /**
     * @dev Allows users to request automatic relays to contracts without
     * calling a specific 'receiveWormholeMessages' endpoint.
     *
     * The relayed endpoint can be:
     * - An arbitrary one with arbitrary calldata specified on the source chain (ExecutionType.ArbitraryCallData).
     * - A specific selector with exactly one 'bytes' argument - the signed VAA (ExecutionType.SingleVAA).
     */
    function receiveWormholeMessages(
        bytes calldata payload,
        bytes[] calldata additionalVaas,
        bytes32 sourceAddress, // Address that called 'sendPayloadToEvm' (either user or WormRouter).
        uint16 sourceChain,
        bytes32 deliveryHash // This can be used to prevent duplicate deliveries.
    ) external payable override onlyOwner {
        require(msg.sender == address(wormholeRelayer), "Only WormholeRelayer can call this function");

        address targetAddress;
        bool success;
        bytes memory returnData;

        ExecutionType executionType = abi.decode(payload, (ExecutionType));

        if (executionType == ExecutionType.ArbitraryCallData) {
            (, targetAddress, bytes memory data) = abi.decode(payload, (ExecutionType, address, bytes));
            (success, returnData) = executeCall(targetAddress, data);
        } else if (executionType == ExecutionType.SingleVAA) {
            (, targetAddress, bytes4 selector) = abi.decode(payload, (ExecutionType, address, bytes4));
            (success, returnData) = executeCallWithSelector(targetAddress, selector, additionalVaas[0]);
        }

        emit CrossChainActionCompleted(sourceChain, sourceAddress, targetAddress, success, returnData);
    }

    // Refactored execution into separate functions for better readability and potential reusability.
    function executeCall(address target, bytes memory data) private returns (bool, bytes memory) {
        return target.call{value: msg.value}(data);
    }

    function executeCallWithSelector(address target, bytes4 selector, bytes memory vaa) private returns (bool, bytes memory) {
        return target.call{value: msg.value}(abi.encodeWithSelector(selector, vaa));
    }
}
