// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/WormRouter.sol";

import "wormhole-solidity-sdk/testing/WormholeRelayerTest.sol";

contract HelloWormholeTest is WormholeRelayerBasicTest {
    event GreetingReceived(string greeting, uint16 senderChain, address sender);

    WormRouter wormRouter;

    function setUpSource() public override {
    }

    function setUpTarget() public override {
        wormRouter = new WormRouter(address(relayerTarget));
    }

    function testTransferTokens() public {
        
    }
}
