import {Address} from 'web3-types';

export interface DeploymentAddress {
  address: Address;
}

export interface Release {
  name: string;
  version: string;
  deployments: Record<string, Record<string, Address>>;
  abi: any[];
}
