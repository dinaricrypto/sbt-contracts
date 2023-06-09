import 'dotenv/config';
import { Wallet } from 'ethers';

export function getWalletsFromMnemonic(mnemonic: string, n: number, account = 0) {
    const wallets: Wallet[] = new Array(n);
    for (let index = 0; index < n; index++) {
        wallets[index] = Wallet.fromMnemonic(mnemonic, `m/44'/60'/${account}'/0/${index}`);
    }
    return wallets;
}

async function main() {
    const mnemonic = process.env['PRINT_MNEMONIC'];
    if (!mnemonic) throw new Error('empty mnemonic');
    console.log('');
    console.log('Mnemonic');
    console.log(mnemonic);

    for (let i = 0; i < 4; i++) {
        const wallets = getWalletsFromMnemonic(mnemonic, 5, i);
        console.log('');
        console.log(`======== Account ${i} ========`);
        wallets.forEach((wallet) => {
            console.log('');
            console.log('Address: ', wallet.address);
            console.log('Key: ', wallet.privateKey);
        });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
