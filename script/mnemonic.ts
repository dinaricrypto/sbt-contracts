import { generateMnemonic } from 'bip39';

async function main() {
    const m = generateMnemonic();
    console.log(m);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
