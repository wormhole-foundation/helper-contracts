// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/Utils.sol";

contract WormRouter is IWormholeReceiver {

    event CrossChainAction(
        uint16 sourceChain, bytes32 sourceAddress, address targetAddress, bool success, bytes returnData
    );

    enum Version {
        ARBITRARY_CALL_DATA,
        ONE_VAA
    }

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

    /**
     * Helpers for requesting automatic relays to either
     *  - arbitrary endpoints with arbitrary calldata specified on source chain (callEvm)
     *  - arbitrary endpoints with exactly one 'bytes' argument - the signed VAA (callEvmWithVAA)
     */

    function callEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory arbitraryCallData,
        uint256 gasLimit,
        uint256 receiverValue,
        address wormRouterAddress
    ) public payable {
        (uint256 value,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit);
        wormholeRelayer.sendPayloadToEvm{value: value}(
            targetChain,
            wormRouterAddress,
            abi.encode(Version.ARBITRARY_CALL_DATA, targetAddress, arbitraryCallData),
            receiverValue,
            gasLimit
        );
    }

    function callEvmWithVAA(
        uint16 targetChain,
        address targetAddress,
        bytes4 selector,
        VaaKey memory vaaKey,
        uint256 gasLimit,
        uint256 receiverValue,
        address wormRouterAddress
    ) public payable {
        (uint256 value,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit);
        VaaKey[] memory vaaKeys = new VaaKey[](1);
        vaaKeys[0] = vaaKey;
        wormholeRelayer.sendVaasToEvm{value: value}(
            targetChain,
            wormRouterAddress,
            abi.encode(Version.ONE_VAA, targetAddress, selector),
            receiverValue,
            gasLimit,
            vaaKeys
        );
    }

    struct CallEvmWithVAA {
        uint16 targetChain;
        address targetAddress;
        bytes4 selector;
        uint256 gasLimit;
        uint256 receiverValue;
        address wormRouterAddress;
    }

    function callMultipleEvmsWithVAA(CallEvmWithVAA[] memory calls, VaaKey memory vaaKey) public payable {
        uint256 length = calls.length;
        for (uint256 i = 0; i < length; i++) {
            CallEvmWithVAA memory call = calls[i];
            callEvmWithVAA(
                call.targetChain, call.targetAddress, call.selector, vaaKey, call.gasLimit, call.receiverValue, call.wormRouterAddress
            );
        }
    }

    struct PerformAction {
        address actionAddress;
        bytes actionCallData;
        uint256 actionMsgValue;
    }

    function performActionsAndCallMultipleEvms(
        PerformAction[] memory actions,
        address vaaEmitter, 
        uint256 index, // action[index] should return a sequence number (uint64) corresponding to an emitted VAA from emitter address 'vaaEmitter'
        CallEvmWithVAA[] memory calls
    ) public payable {
        VaaKey memory vaaKey;
        for(uint256 i=0; i<actions.length; i++) {
            PerformAction memory action = actions[i];
            (bool success, bytes memory returnData) = action.actionAddress.call{value: action.actionMsgValue}(action.actionCallData);

            if(i == index) {
                // Assume that returnData is one 'sequence number'
                require(success, "Call to Wormhole Integration contact failed");
                (uint64 sequence) = abi.decode(returnData, (uint64));

                vaaKey = VaaKey({chainId: chainId, emitterAddress: toWormholeFormat(vaaEmitter), sequence: sequence});
            }
        }
        callMultipleEvmsWithVAA(calls, vaaKey);
    }
}
