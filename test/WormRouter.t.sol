// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/WormRouter.sol";

import "wormhole-solidity-sdk/testing/WormholeRelayerTest.sol";
import "wormhole-solidity-sdk/WormholeRelayerSDK.sol";

contract WormRouterTest is WormholeRelayerBasicTest {
    event GreetingReceived(string greeting, uint16 senderChain, address sender);

    WormRouter wormRouterTarget;
    ERC20Mock public token;
    uint256 constant GAS_LIMIT = 150_000;

    function setUpSource() public override {
        token = createAndAttestToken(sourceChain);
    }

    function setUpTarget() public override {
        wormRouterTarget = new WormRouter(address(relayerTarget), targetChain);
    }

    function testTransferTokens() public {
        uint256 amount = 19e17;
        address recipient = 0x1234567890123456789012345678901234567890;

        token.approve(address(tokenBridgeSource), amount);
        uint64 sequence =
            tokenBridgeSource.transferTokens(address(token), amount, targetChain, toWormholeFormat(recipient), 0, 0);

        VaaKey[] memory vaaKeys = new VaaKey[](1);
        vaaKeys[0] = VaaKey({
            chainId: sourceChain,
            sequence: sequence,
            emitterAddress: toWormholeFormat(address(tokenBridgeSource))
        });

        (uint256 value,) = relayerSource.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);

        relayerSource.sendVaasToEvm{value: value}(
            targetChain,
            address(wormRouterTarget),
            abi.encode(Version.ONE_VAA, address(tokenBridgeTarget), ITokenBridge.completeTransfer.selector),
            0,
            GAS_LIMIT,
            vaaKeys
        );

        performDelivery();

        vm.selectFork(targetFork);
        address wormholeWrappedToken = tokenBridgeTarget.wrappedAsset(sourceChain, toWormholeFormat(address(token)));
        assertEq(IERC20(wormholeWrappedToken).balanceOf(recipient), amount);
    }
}
