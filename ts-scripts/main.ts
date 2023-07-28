import { checkFlag } from "./utils";
import { deployTokenBridgeHelpers, deployWormRouter } from "./deploy";
import { deployMockToken } from "./deploy-mock-tokens";

async function main() {
  if (checkFlag("--deployWormRouter")) {
    await deployWormRouter();
    return;
  }
  if (checkFlag("--deployMockToken")) {
    await deployMockToken();
    return;
  }
  if (checkFlag("--deployTokenBridgeHelpers")) {
    await deployTokenBridgeHelpers();
    return;
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
