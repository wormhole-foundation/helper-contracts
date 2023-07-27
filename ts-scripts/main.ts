import { checkFlag } from "./utils";
import { deploy } from "./deploy";
import { deployMockToken } from "./deploy-mock-tokens";

async function main() {
  if (checkFlag("--deployWormRouter")) {
    await deploy();
    return;
  }
  if (checkFlag("--deployMockToken")) {
    await deployMockToken();
    return;
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
