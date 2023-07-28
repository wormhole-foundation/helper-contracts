// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import "wormhole-solidity-sdk/interfaces/IERC20.sol";
import "wormhole-solidity-sdk/testing/ERC20Mock.sol";

import "wormhole-solidity-sdk/testing/WormholeRelayerTest.sol";

import "wormhole-solidity-sdk/WormholeRelayerSDK.sol";
import "wormhole-solidity-sdk/Utils.sol";

import "forge-std/console.sol";

import "../src/WormRouter.sol";
import "../src/TokenBridgeHelpers.sol";

contract TokenBridgeHelpersTest is WormholeRelayerTest {

    mapping(uint16 => WormRouter) wormRouters;

    
    TokenBridgeHelpers tokenBridgeHelpersAvax;

    constructor() WormholeRelayerTest() {
        ChainInfo[] memory chains = new ChainInfo[](4);
        chains[0] = chainInfosTestnet[4];
        chains[1] = chainInfosTestnet[16];
        chains[2] = chainInfosTestnet[6];
        chains[3] = chainInfosTestnet[14];
        setActiveForks(chains);
    }

    function setUpFork(ActiveFork memory fork) public override {
        wormRouters[fork.chainId] = new WormRouter(address(fork.relayer), fork.chainId);

        if(fork.chainId == 6) {
            tokenBridgeHelpersAvax = new TokenBridgeHelpers(address(fork.relayer), address(fork.wormhole), address(fork.tokenBridge));
        }

    }

    function testSendFromAvax() public {
        vm.recordLogs();
        ActiveFork memory avalanche = activeForks[6];
        vm.selectFork(avalanche.fork);

        // Only doing actions on Avalanche!

        uint16[2] memory chains = [uint16(16), uint16(14)];

        uint16[] memory attestChains = new uint16[](2);
        address[] memory tokenBridgesArray = new address[](2);
        address[] memory wormRoutersArray = new address[](2);
        for(uint256 i=0; i<chains.length; i++) {
            attestChains[i] = chains[i];
            tokenBridgesArray[i] = address(activeForks[chains[i]].tokenBridge);
            wormRoutersArray[i] = address(wormRouters[chains[i]]);
        }

        ERC20Mock token = new ERC20Mock("Test Token", "TST");
        token.mint(address(this), 5000e18);

        
        // Transaction to attest token on Moonbeam and Celo
        tokenBridgeHelpersAvax.attestToken{value: tokenBridgeHelpersAvax.quoteAttestToken(attestChains)}(
            address(token),
            attestChains,
            tokenBridgesArray,
            wormRoutersArray
        );
        
        performDelivery();
        
        address recipient = 0x1234567890123456789012345678901234567890;
        uint256 amount = 2e18;

        vm.selectFork(avalanche.fork);

        token.approve(address(tokenBridgeHelpersAvax), amount);
        // Transaction to send token from Avalanche to Celo

        uint16 targetChain = 14;
        tokenBridgeHelpersAvax.transferTokens{value: tokenBridgeHelpersAvax.quoteTransferTokens(targetChain)}(
            address(token),
            amount,
            targetChain,
            recipient,
            address(activeForks[targetChain].tokenBridge),
            address(wormRouters[targetChain])
        );

        performDelivery();

        // Check if the transfer was received
        vm.selectFork(activeForks[targetChain].fork);
        address wormholeWrappedToken = activeForks[targetChain].tokenBridge.wrappedAsset(6, toWormholeFormat(address(token)));
        assertEq(IERC20(wormholeWrappedToken).balanceOf(recipient), amount);
        

    }
}
