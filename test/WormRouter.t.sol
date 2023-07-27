// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/WormRouter.sol";

import "wormhole-solidity-sdk/testing/WormholeRelayerTest.sol";
import "wormhole-solidity-sdk/WormholeRelayerSDK.sol";

contract WormRouterTest is WormholeRelayerBasicTest {
    event GreetingReceived(string greeting, uint16 senderChain, address sender);

    WormRouter wormRouterSource;
    WormRouter wormRouterTarget;
    ERC20Mock public token;
    uint256 constant GAS_LIMIT = 150_000;

    function setUpSource() public override {
        token = createAndAttestToken(sourceChain);
        wormRouterSource = new WormRouter(address(relayerSource), sourceChain);
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

    function testTransferTokensUsingPerformActionAndCallMultipleEvms() public {
        uint256 amount = 19e17;
        address recipient = 0x1234567890123456789012345678901234567890;

        token.approve(address(wormRouterSource), amount);

        CallEvmWithVAA memory call = CallEvmWithVAA({
            targetChain: targetChain,
            targetAddress: address(tokenBridgeTarget),
            selector: ITokenBridge.completeTransfer.selector,
            gasLimit: GAS_LIMIT,
            receiverValue: 0,
            wormRouterAddress: address(wormRouterTarget)
        });

        CallEvmWithVAA[] memory calls = new CallEvmWithVAA[](1);
        calls[0] = call;

        PerformAction memory sendTokenToWormRouter = PerformAction({
            actionAddress: address(token),
            actionCallData: abi.encodeCall(IERC20.transferFrom, (address(this), address(wormRouterSource), amount)),
            actionMsgValue: 0
        });

        PerformAction memory approveTokenFromWormRouterToTokenBridge = PerformAction({
            actionAddress: address(token),
            actionCallData: abi.encodeCall(IERC20.approve, (address(tokenBridgeSource), amount)),
            actionMsgValue: 0
        });

        PerformAction memory sendTokenToTargetChain = PerformAction({
            actionAddress: address(tokenBridgeSource),
            actionCallData: abi.encodeCall(
                ITokenBridge.transferTokens, (address(token), amount, targetChain, toWormholeFormat(recipient), 0, 0)
                ),
            actionMsgValue: 0
        });

        PerformAction[] memory actions = new PerformAction[](3);
        actions[0] = sendTokenToWormRouter;
        actions[1] = approveTokenFromWormRouterToTokenBridge;
        actions[2] = sendTokenToTargetChain;

        (uint256 value,) = relayerSource.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);

        wormRouterSource.performActionsAndCallMultipleEvms{value: value}(actions, address(tokenBridgeSource), 2, calls);

        performDelivery();

        vm.selectFork(targetFork);
        address wormholeWrappedToken = tokenBridgeTarget.wrappedAsset(sourceChain, toWormholeFormat(address(token)));
        assertEq(IERC20(wormholeWrappedToken).balanceOf(recipient), amount);
    }
}
