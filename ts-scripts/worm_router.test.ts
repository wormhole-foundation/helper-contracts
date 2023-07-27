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
  transferFromEth,
  parseSequenceFromLogEth,
} from "@certusone/wormhole-sdk";

import {
  WormRouter,
  WormRouter__factory,
  ERC20Mock__factory,
  IERC20__factory,
} from "./ethers-contracts";

import { IERC20Interface } from "./ethers-contracts/IERC20";

import { ITokenBridge__factory } from "@certusone/wormhole-sdk/lib/cjs/ethers-contracts";
import { IWormholeRelayer__factory } from "@certusone/wormhole-sdk/lib/cjs/ethers-contracts/factories/IWormholeRelayerTyped.sol";

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

  const receipt = await transferFromEth(
    CONTRACTS[environment][sourceChain].token_bridge || "",
    getWallet(CHAINS[sourceChain]),
    token,
    amount,
    CHAINS[targetChain],
    tryNativeToUint8Array(recipient, sourceChain)
  );

  const sequence = parseSequenceFromLogEth(
    receipt,
    CONTRACTS[environment][sourceChain].core || ""
  );

  console.log(`Sequence number of Token Bridge VAA: ${sequence}`);

  const price = await transferTokenCost(
    sourceChain,
    targetChain,
    optionalParams
  );

  return IWormholeRelayer__factory.connect(
    getChain(CHAINS[sourceChain]).wormholeRelayer,
    getWallet(CHAINS[sourceChain])
  )[
    "sendVaasToEvm(uint16,address,bytes,uint256,uint256,(uint16,bytes32,uint64)[])"
  ](
    CHAINS[targetChain],
    getWormRouter(CHAINS[targetChain]).address,
    ethers.utils.defaultAbiCoder.encode(
      ["uint8", "address", "bytes4"],
      [
        1,
        CONTRACTS[environment][targetChain].token_bridge,
        ITokenBridge__factory.createInterface().getSighash("completeTransfer"),
      ]
    ),
    0,
    GAS_LIMIT,
    [
      {
        chainId: CHAINS[sourceChain],
        emitterAddress: tryNativeToUint8Array(
          CONTRACTS[environment][sourceChain].token_bridge || "",
          sourceChain
        ),
        sequence: sequence,
      },
    ],
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

      // Approve the TokenBridge contract to use 'arbitraryTokenAmount' of our test token
      const approveTx = await testToken
        .approve(
          CONTRACTS["TESTNET"][CHAIN_ID_TO_NAME[sourceChain]].token_bridge ||
            "",
          arbitraryTokenAmount
        )
        .then(wait);
      console.log(
        `TokenBridge contract approved to spend ${ethers.utils.formatEther(
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
