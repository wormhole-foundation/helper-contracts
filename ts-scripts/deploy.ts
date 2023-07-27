import { WormRouter__factory } from "./ethers-contracts"
import {
  loadConfig,
  getWallet,
  storeDeployedAddresses,
  getChain,
  loadDeployedAddresses,
} from "./utils"

export async function deploy() {
  const config = loadConfig()

  const deployed = loadDeployedAddresses()
  for (const chainId of config.chains.map(c => c.chainId)) {
    const chain = getChain(chainId)
    const signer = getWallet(chainId)

    const wormRouter = await new WormRouter__factory(signer).deploy(
      chain.wormholeRelayer, chainId
    )
    await wormRouter.deployed()

    deployed.wormRouter[chainId] = wormRouter.address
    
    console.log(
      `Worm Router deployed to ${wormRouter.address} on ${chain.description} (chain ${chainId})`
    )
  }

  storeDeployedAddresses(deployed)
}
