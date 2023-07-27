import { describe, expect, test } from "@jest/globals";
import { ethers } from "ethers";
import {
  getWormRouter,
  getChain,
  getWallet,
  loadDeployedAddresses as getDeployedAddresses,
  wait,
} from "./utils";

import {
  CHAIN_ID_TO_NAME,
  Network,
  ChainName,
  relayer,
  CONTRACTS,
  CHAINS,
  tryNativeToHexString,
  tryNativeToUint8Array,
} from "@certusone/wormhole-sdk";

import {
  WormRouter,
  WormRouter__factory,
  ERC20Mock__factory,
  IERC20__factory,
} from "./ethers-contracts";

import { IERC20Interface } from "./ethers-contracts/IERC20";

import {
  CallEvmWithVAAStruct,
  PerformActionStruct,
} from "./ethers-contracts/WormRouter";
import { ITokenBridge__factory } from "@certusone/wormhole-sdk/lib/cjs/ethers-contracts";

const sourceChain = 6;
const targetChain = 14;

type TransferTokenOptionalParams = {
  environment?: Network;
  deliveryProviderAddress?: string;
};

function transferTokenCost(
  sourceChain: ChainName,
  targetChain: ChainName,
  optionalParams?: TransferTokenOptionalParams
): Promise<ethers.BigNumberish> {
  return relayer.getPrice(sourceChain, targetChain, 150000, optionalParams);
}

async function transferToken(
  token: string,
  amount: ethers.BigNumberish,
  sourceChain: ChainName,
  targetChain: ChainName,
  recipient: string,
  overrides?: ethers.PayableOverrides,
  optionalParams?: TransferTokenOptionalParams
): Promise<ethers.ContractTransaction> {
  if (
    ethers.BigNumber.from(overrides?.value).lt(
      await transferTokenCost(sourceChain, targetChain, optionalParams)
    )
  ) {
    throw Error("Not enough payment for relaying of the token");
  }

  const GAS_LIMIT = 150000;

  const environment: Network = optionalParams?.environment || "TESTNET";

  const callEvmWithVaa: CallEvmWithVAAStruct = {
    targetChain: CHAINS[targetChain],
    targetAddress: CONTRACTS[environment][targetChain].token_bridge || "",
    selector:
      ITokenBridge__factory.createInterface().getSighash("completeTransfer"),
    gasLimit: GAS_LIMIT,
    receiverValue: 0,
    wormRouterAddress: getWormRouter(CHAINS[targetChain]).address,
  };

  const tokenBridgeSource =
    CONTRACTS[environment][sourceChain].token_bridge || "";

  const sendTokenToWormRouter: PerformActionStruct = {
    actionAddress: token,
    actionCallData: IERC20__factory.createInterface().encodeFunctionData(
      "transferFrom",
      [
        getWallet(CHAINS[sourceChain]).address,
        getWormRouter(CHAINS[sourceChain]).address,
        amount,
      ]
    ),
    actionMsgValue: 0,
  };

  const approveTokenFromWormRouterToTokenBridge: PerformActionStruct = {
    actionAddress: token,
    actionCallData: IERC20__factory.createInterface().encodeFunctionData(
      "approve",
      [tokenBridgeSource, amount]
    ),
    actionMsgValue: 0,
  };

  const sendTokenToTargetChain: PerformActionStruct = {
    actionAddress: tokenBridgeSource || "",
    actionCallData: ITokenBridge__factory.createInterface().encodeFunctionData(
      "transferTokens",
      [
        token,
        amount,
        CHAINS[targetChain],
        tryNativeToUint8Array(recipient, "ethereum"),
        0,
        0,
      ]
    ),
    actionMsgValue: 0,
  };

  const price = await transferTokenCost(
    sourceChain,
    targetChain,
    optionalParams
  );

  return getWormRouter(CHAINS[sourceChain]).performActionsAndCallMultipleEvms(
    [
      sendTokenToWormRouter,
      approveTokenFromWormRouterToTokenBridge,
      sendTokenToTargetChain,
    ],
    tokenBridgeSource,
    2,
    [callEvmWithVaa],
    { value: price }
  );
}

describe("Worm Router Integration Tests on Testnet", () => {
  test(
    "Tests the sending of a token",
    async () => {
      // Token Bridge can only deal with 8 decimal places
      // So we send a multiple of 10^10, since this MockToken has 18 decimal places
      const arbitraryTokenAmount = ethers.BigNumber.from(
        new Date().getTime() % 10 ** 7
      ).mul(10 ** 10);

      const testToken = ERC20Mock__factory.connect(
        getDeployedAddresses().erc20s[sourceChain][0],
        getWallet(sourceChain)
      );

      const wormholeWrappedTestTokenAddressOnTargetChain =
        await ITokenBridge__factory.connect(
          getChain(targetChain).tokenBridge,
          getWallet(targetChain)
        ).wrappedAsset(
          sourceChain,
          tryNativeToUint8Array(testToken.address, "ethereum")
        );
      const wormholeWrappedTestTokenOnTargetChain = ERC20Mock__factory.connect(
        wormholeWrappedTestTokenAddressOnTargetChain,
        getWallet(targetChain)
      );

      const walletTargetChainAddress = getWallet(targetChain).address;

      const sourceWormRouterContract = getWormRouter(sourceChain);
      const targetWormRouterContract = getWormRouter(targetChain);

      const walletOriginalBalanceOfWrappedTestToken =
        await wormholeWrappedTestTokenOnTargetChain.balanceOf(
          walletTargetChainAddress
        );

      const cost = await transferTokenCost(
        CHAIN_ID_TO_NAME[sourceChain],
        CHAIN_ID_TO_NAME[targetChain],
        { environment: "TESTNET" }
      );
      console.log(
        `Cost of sending the tokens: ${ethers.utils.formatEther(
          cost
        )} testnet AVAX`
      );

      // Approve the WormRouter contract to use 'arbitraryTokenAmount' of our test token
      const approveTx = await testToken
        .approve(sourceWormRouterContract.address, arbitraryTokenAmount)
        .then(wait);
      console.log(
        `WormRouter contract approved to spend ${ethers.utils.formatEther(
          arbitraryTokenAmount
        )} of our test token`
      );

      console.log(
        `Sending ${ethers.utils.formatEther(
          arbitraryTokenAmount
        )} of the test token`
      );

      const tx = await transferToken(
        testToken.address,
        arbitraryTokenAmount,
        CHAIN_ID_TO_NAME[sourceChain],
        CHAIN_ID_TO_NAME[targetChain],
        getWallet(targetChain).address,
        { value: cost },
        { environment: "TESTNET" }
      );

      console.log(`Transaction hash: ${tx.hash}`);
      await tx.wait();
      console.log(
        `See transaction at: https://testnet.snowtrace.io/tx/${tx.hash}`
      );

      await new Promise((resolve) => setTimeout(resolve, 1000 * 15));

      /*
        console.log("Checking relay status");
        const res = await getStatus(CHAIN_ID_TO_NAME[sourceChain], tx.hash);
        console.log(`Status: ${res.status}`);
        console.log(`Info: ${res.info}`); */

      console.log(`Seeing if token was sent`);
      const walletCurrentBalanceOfWrappedTestToken =
        await wormholeWrappedTestTokenOnTargetChain.balanceOf(
          walletTargetChainAddress
        );

      expect(
        walletCurrentBalanceOfWrappedTestToken
          .sub(walletOriginalBalanceOfWrappedTestToken)
          .toString()
      ).toBe(arbitraryTokenAmount.toString());
    },
    60 * 1000
  ); // timeout
});
