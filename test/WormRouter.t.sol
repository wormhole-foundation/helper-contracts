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

    function testTransferTokensUsingPerformActionAndCallMultipleEvms() public {
        uint256 amount = 19e17;
        address recipient = 0x1234567890123456789012345678901234567890;

        token.approve(address(wormRouterSource), amount);

        WormRouter.CallEvmWithVAA memory call = WormRouter.CallEvmWithVAA({
            targetChain: targetChain,
            targetAddress: address(tokenBridgeTarget),
            selector: ITokenBridge.completeTransfer.selector,
            gasLimit: GAS_LIMIT,
            receiverValue: 0,
            wormRouterAddress: address(wormRouterTarget)
        });

        WormRouter.CallEvmWithVAA[] memory calls = new WormRouter.CallEvmWithVAA[](1);
        calls[0] = call;

        WormRouter.PerformAction memory sendTokenToWormRouter = WormRouter.PerformAction({
            actionAddress: address(token),
            actionCallData: abi.encodeCall(
                IERC20.transferFrom, (address(this), address(wormRouterSource), amount)
            ),
            actionMsgValue: 0
        });

        WormRouter.PerformAction memory approveTokenFromWormRouterToTokenBridge = WormRouter.PerformAction({
            actionAddress: address(token),
            actionCallData: abi.encodeCall(
                IERC20.approve, (address(tokenBridgeSource),amount)
            ),
            actionMsgValue: 0
        });

        WormRouter.PerformAction memory sendTokenToTargetChain = WormRouter.PerformAction({
            actionAddress: address(tokenBridgeSource),
            actionCallData: abi.encodeCall(
                ITokenBridge.transferTokens, (address(token), amount, targetChain, toWormholeFormat(recipient), 0, 0)
            ),
            actionMsgValue: 0
        });

        WormRouter.PerformAction[] memory actions = new WormRouter.PerformAction[](3);
        actions[0] = sendTokenToWormRouter;
        actions[1] = approveTokenFromWormRouterToTokenBridge;
        actions[2] = sendTokenToTargetChain;

        (uint256 value,) = relayerSource.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);

        wormRouterSource.performActionsAndCallMultipleEvms{value: value}(
            actions,
            address(tokenBridgeSource),
            2,
            calls
        );

        performDelivery();

        vm.selectFork(targetFork);
        address wormholeWrappedToken = tokenBridgeTarget.wrappedAsset(sourceChain, toWormholeFormat(address(token)));
        assertEq(IERC20(wormholeWrappedToken).balanceOf(recipient), amount);
    }
}
