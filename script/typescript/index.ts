import { Argument, Command, InvalidArgumentError } from "commander";
import * as fs from "fs";
import * as _ from "lodash";
import * as path from "path";
import * as semver from "semver";
import { Address } from "web3-types";
import * as Web3Utils from "web3-utils";

import { DeploymentAddress, Release } from "./types";

const program = new Command();

program
  .name("scripts")
  .description("Complementary CLI for smart contract deployment");

program
  .command("bundle")
  .argument("<artifactDirectory>", "Directory of artifacts")
  .argument("<releaseDirectory>", "Directory of artifacts")
  .argument("<outputDirectory>", "Directory for output")
  .addArgument(
    new Argument("<environment>", "Environment of deployment").choices([
      "staging",
      "production",
    ]),
  )
  .argument(
    "<version>",
    "Version of release artifact",
    (value: string, _previous: any) => {
      if (!semver.valid(value)) {
        throw new InvalidArgumentError("Version must follow semver format");
      }
      return value;
    },
  )
  .description("Bundles artifacts into release files")
  .action(function (
    artifactDirectory: string,
    releaseDirectory: string,
    outputDirectory: string,
    environment: string,
    version: string,
  ) {
    const contractToDeployment: Record<string, Record<string, Address>> = {};

    // Populate contractToDeployment from artifacts
    if (fs.existsSync(path.join(artifactDirectory, environment))) {
      const artifacts = fs.readdirSync(
        path.join(artifactDirectory, environment),
      );
      for (const artifact of artifacts) {
        const m = /(\d+)\.(.+)\.json$/gm.exec(artifact);
        // Skip if no matches found
        if (m === null) {
          continue;
        }

        // Read file
        const fp = path.join(artifactDirectory, environment, artifact),
          deploymentAddress: DeploymentAddress = JSON.parse(
            fs.readFileSync(fp, "utf-8"),
          );

        const chainId = m[1],
          contractName = m[2],
          address = Web3Utils.toChecksumAddress(deploymentAddress.address);

        if (!(contractName in contractToDeployment)) {
          contractToDeployment[contractName] = {};
        }
        contractToDeployment[contractName][chainId] = address;
      }
    }

    // Create releases directory
    if (!fs.existsSync(outputDirectory)) {
      fs.mkdirSync(outputDirectory);
    }

    // Generate release file from existing release files
    for (const contractName in contractToDeployment) {
      // Special handling for DShare and WrappedDshare
      const releaseFilename = `${_.snakeCase(contractName.replace("DShare", "Dshare"))}.json`,
        releaseFilepath = path.join(
          releaseDirectory,
          `v${version}`,
          releaseFilename,
        ),
        abiFilename = path.join(
          "out",
          `${contractName}.sol`,
          `${contractName}.json`,
        );

      // Create new release or load from existing
      const release: Release = fs.existsSync(releaseFilepath)
        ? JSON.parse(fs.readFileSync(releaseFilepath, "utf-8"))
        : {
            name: contractName,
            version: version,
            deployments: { production: {}, staging: {} },
            abi: [],
          };

      // Update ABI from contract output
      if (fs.existsSync(abiFilename)) {
        release.abi = JSON.parse(fs.readFileSync(abiFilename, "utf-8"))["abi"];
      }

      // Update deployments
      release.deployments[environment] = _.merge(
        release.deployments[environment],
        contractToDeployment[contractName],
      );

      // Sort deployments
      release.deployments[environment] = Object.keys(
        release.deployments[environment],
      )
        .sort()
        .reduce((obj: Record<string, Address>, key: string) => {
          obj[key] = release.deployments[environment][key];
          return obj;
        }, {});

      // Write files
      const outputFilePath = path.join(outputDirectory, releaseFilename);
      console.log(`Writing to ${outputFilePath}`);
      fs.writeFileSync(outputFilePath, JSON.stringify(release));
    }
  });

async function main() {
  await program.parseAsync();
}

main();
