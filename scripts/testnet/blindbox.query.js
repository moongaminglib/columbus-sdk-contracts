const { Conflux } = require("js-conflux-sdk");
let env = require('../env.json');
let contracts = require('./contracts.json');
let json_rpc_url = env.json_rpc;
let chainId = env.chainId;

const cfx = new Conflux({
    url: json_rpc_url,
    networkId: chainId
});
const sourceContract = require('../../build/contracts/NFTBlindBox.json');
const { assert } = require("js-conflux-sdk/src/util");

let contract_address = contracts.blindbox_addr;

const contract = cfx.Contract({
    abi: sourceContract.abi,
    address: contract_address,
});

async function main() {
  
}
main().catch(e => console.error(e));
