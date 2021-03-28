const { Conflux, util } = require('js-conflux-sdk');

let env = require('../../env.json');
let contracts = require('./contracts.json');
let json_rpc_url = env.json_rpc;
let PRIVATE_KEY = env.adminPrivateKey;
let chainId = env.chainId;

const cfx = new Conflux({
  url: json_rpc_url,
  networkId:env['chainId']
});

const sourceContract = require('../../build/contracts/Genesis.json');

let contract_address = contracts.nft_addr;

const contract = cfx.Contract({
  abi: sourceContract.abi,
  address: contract_address,
});

async function main() {
  let _id = 1
  await ownersOf(_id);

  let nextTokenId = await contract.getNextTokenID().call();

  console.log('nextTokenId =>', nextTokenId);
}

async function ownersOf(_id)
{
  let addreses = await contract.ownerOf(_id).call();

  console.log("token_id" + _id, " ownerAddress =>" +addreses);
}

main().catch(e => console.error(e));
