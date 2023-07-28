import {
  WormRouter__factory,
  TokenBridgeHelpers__factory,
} from "./ethers-contracts";
import {
  loadConfig,
  getWallet,
  storeDeployedAddresses,
  getChain,
  loadDeployedAddresses,
} from "./utils";

export async function deployWormRouter() {
  const config = loadConfig();

  const deployed = loadDeployedAddresses();
  for (const chainId of config.chains.map((c) => c.chainId)) {
    const chain = getChain(chainId);
    const signer = getWallet(chainId);

    const wormRouter = await new WormRouter__factory(signer).deploy(
      chain.wormholeRelayer,
      chainId
    );
    await wormRouter.deployed();

    deployed.wormRouter[chainId] = wormRouter.address;

    console.log(
      `Worm Router deployed to ${wormRouter.address} on ${chain.description} (chain ${chainId})`
    );
  }

  storeDeployedAddresses(deployed);
}

export async function deployTokenBridgeHelpers() {
  const config = loadConfig();

  const deployed = loadDeployedAddresses();
  for (const chainId of config.chains.map((c) => c.chainId)) {
    const chain = getChain(chainId);
    const signer = getWallet(chainId);

    const tokenBridgeHelpers = await new TokenBridgeHelpers__factory(
      signer
    ).deploy(chain.wormholeRelayer, chain.wormhole, chain.tokenBridge);
    await tokenBridgeHelpers.deployed();

    deployed.tokenBridgeHelpers[chainId] = tokenBridgeHelpers.address;

    console.log(
      `TokenBridgeHelpers deployed to ${tokenBridgeHelpers.address} on ${chain.description} (chain ${chainId})`
    );
  }

  storeDeployedAddresses(deployed);
}
