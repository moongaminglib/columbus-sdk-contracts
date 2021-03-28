const { Conflux, format } = require("js-conflux-sdk");
let env = require('../../env.json');
let contracts = require('./contracts.json');
let assets = require('./assets.json');

let json_rpc_url = env.json_rpc;
let PRIVATE_KEY = env.adminPrivateKey;
let chainId = env.chainId;

let nft_addr = contracts.nft_addr;
let cMoonToken = assets.cMOON;

const sourceContract = require('../../build/contracts/NFTStake.json');

const cfx = new Conflux({ url: json_rpc_url, networkId: chainId,
    logger: console
  });

const account = cfx.wallet.addPrivateKey(PRIVATE_KEY);
let devAddr = account.address;

console.log('from=>', account.address);

const contract = cfx.Contract({
    bytecode: sourceContract.bytecode,
    abi: sourceContract.abi
});

async function main()
{
  await contract.constructor(nft_addr, cMoonToken, devAddr)
  .sendTransaction({ from: account , chainId: chainId})
  .confirmed()
  .then((receipt) => {
      console.log("nft_stake_addr:", format.hexAddress(receipt.contractCreated))
  })
  .catch(error => {console.log(error); process.exit(1)});

}

main().catch(e => console.error(e));
