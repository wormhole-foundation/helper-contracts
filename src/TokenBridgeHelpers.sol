// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-solidity-sdk/interfaces/ITokenBridge.sol";
import "wormhole-solidity-sdk/Utils.sol";

contract TokenBridgeHelpers {

    IWormholeRelayer public immutable wormholeRelayer;
    IWormhole public immutable wormhole;
    ITokenBridge public immutable tokenBridge;

    constructor(address _wormholeRelayer, address _wormhole, address _tokenBridge) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        tokenBridge = ITokenBridge(_tokenBridge);
        wormhole = IWormhole(_wormhole);
    }

    uint256 constant GAS_LIMIT_TRANSFER = 150_000;
    uint256 constant GAS_LIMIT_ATTEST = 550_000;

    function quoteTransferTokens(uint16 recipientChain) public view returns (uint256 price) {
        (uint256 transferCost,) = wormholeRelayer.quoteEVMDeliveryPrice(recipientChain, 0, GAS_LIMIT_TRANSFER);
        price = transferCost + wormhole.messageFee();
    }

    // Transfers 'amount' of IERC20 token 'token' to 'recipient' on chain 'recipientChain'
    // and also requests a 'relay' of the resulting VAA to the TokenBridge contract on the recipient chain
    function transferTokens(
        address token,
        uint256 amount,
        uint16 recipientChain,
        address recipient,
        address recipientChainTokenBridgeAddress,
        address recipientChainWormRouterAddress
    ) public payable returns (uint64 transferSequence, uint64 deliverySequence) {
        uint256 cost = quoteTransferTokens(recipientChain);
        require(msg.value == cost, "Incorrect msg.value");

        // Retrieves the token from the user, and approves the Token Bridge to spend the token
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(address(tokenBridge), amount);

        // Creates a Token Bridge VAA representing the sending of the token
        transferSequence = tokenBridge.transferTokens{value: wormhole.messageFee()}(token, amount, recipientChain, toWormholeFormat(recipient), 0, 0);
        
        VaaKey memory vaaKey = VaaKey({
            chainId: wormhole.chainId(),
            sequence: transferSequence,
            emitterAddress: toWormholeFormat(address(tokenBridge))
        });
        VaaKey[] memory vaaKeys = new VaaKey[](1);
        vaaKeys[0] = vaaKey;

        // Use the Wormhole Relayer to request delivery of the token bridge VAA (paying the corresponding fee)
        deliverySequence = wormholeRelayer.sendVaasToEvm{value: cost - wormhole.messageFee()}(
            recipientChain,
            recipientChainWormRouterAddress,
            abi.encode(1, recipientChainTokenBridgeAddress, ITokenBridge.completeTransfer.selector),
            0,
            GAS_LIMIT_TRANSFER,
            vaaKeys
        );
    }

    function quoteAttestToken(
        uint16[] memory attestChains
    ) public view returns (uint256 cost) {
        cost = wormhole.messageFee();
        for(uint256 i=0; i<attestChains.length; i++) {
            (uint256 deliveryCost,) = wormholeRelayer.quoteEVMDeliveryPrice(attestChains[i], 0, GAS_LIMIT_ATTEST);
            cost += deliveryCost; 
        }
    }

    // Attests token 'token' to the TokenBridge
    // and also requests a 'relay' of the resulting VAA to the TokenBridge contract on each chain in 'attestChains'
    function attestToken(
        address token,
        uint16[] memory attestChains,
        address[] memory attestTokenBridgeAddresses,
        address[] memory attestWormRouterAddresses
    ) public payable returns (uint64 attestSequence, uint64[] memory deliverySequences) {

        // Attest 'token' to the TokenBridge
        attestSequence = tokenBridge.attestToken{value: wormhole.messageFee()}(token, 0);

        uint256 length = attestChains.length;
        deliverySequences = new uint64[](length);
        for(uint256 i=0; i<length; i++) {
            (uint256 deliveryCost,) = wormholeRelayer.quoteEVMDeliveryPrice(attestChains[i], 0, GAS_LIMIT_ATTEST);

            VaaKey memory vaaKey = VaaKey({
                chainId: wormhole.chainId(),
                sequence: attestSequence,
                emitterAddress: toWormholeFormat(address(tokenBridge))
            });
            VaaKey[] memory vaaKeys = new VaaKey[](1);
            vaaKeys[0] = vaaKey;

            // Use the WormholeRelayer to request delivery of the resulting attestation VAA to the chain attestChains[i]
            deliverySequences[i] = wormholeRelayer.sendVaasToEvm{value: deliveryCost}(
                attestChains[i],
                attestWormRouterAddresses[i],
                abi.encode(1, attestTokenBridgeAddresses[i], ITokenBridge.createWrapped.selector),
                0,
                GAS_LIMIT_ATTEST,
                vaaKeys
            );    
        }
    }


}
