const { Conflux, format } = require("js-conflux-sdk");
let env = require('../../env.json');
let contracts = require('./contracts.json');
let json_rpc_url = env.json_rpc;
let PRIVATE_KEY = env.adminPrivateKey;

let chainId = env.chainId;

const cfx = new Conflux({
    url: json_rpc_url,
    networkId: chainId
});
const sourceContract = require('../../build/contracts/NFTBlindBox.json');
const { assert } = require("js-conflux-sdk/src/util");

const account = cfx.wallet.addPrivateKey(PRIVATE_KEY);
let from = account.address;
console.log('from =>', from);

let contract_address = contracts.blindbox_addr;

const contract = cfx.Contract({
    abi: sourceContract.abi,
    address: contract_address,
});

async function main() {
    // open sale
    await onSale(2, true, 0);
    // set Price
    await setPrice();
}


async function setPrice()
{
    console.log('setPrice');
    let stageNum = 1;
    let fc_price = format.big(30 * 1e18).toFixed();
    let cmoon_price = format.big(1 * 1e18).toFixed();
    let cfx_price = format.big(0.1 * 1e18).toFixed();

    let estimate = await contract.setPrices(stageNum, fc_price, cmoon_price, cfx_price).estimateGasAndCollateral({from: from});
    let data = await contract.setPrices(stageNum, fc_price, cmoon_price, cfx_price).data;

    await packTransaction(estimate, data);
}

async function onSale(stageNum, sale, height) {
    console.log('onSale =>', stageNum, sale, height);
    let estimate = await contract.setSale(stageNum, sale, height).estimateGasAndCollateral({from: from});
    let data = await contract.setSale(stageNum, sale, height).data;

    await packTransaction(estimate, data);
}

function encodeParameters(types, values) {
    const abi = new ethers.utils.AbiCoder();
    return abi.encode(types, values);
}

async function packTransaction(estimate, transData, value = 0)
{
   // check
   let data = transData;
   let nonce = await cfx.getNextNonce(from);
   const epochNumber = await cfx.getEpochNumber();

   console.log(estimate);

   value = value * 10 ** 18;
   const tx = await account.signTransaction({
     nonce,
     gasPrice: 1,
     gas: parseInt(estimate.gasUsed.toString() * 2),
     to: contract_address,
     value: value,
     storageLimit: parseInt(estimate.storageCollateralized.toString() * 2),
     epochHeight: epochNumber,
     chainId: chainId,
     data: data,
   });

   const receipt = await cfx.sendRawTransaction(tx.serialize()).executed(); // await till confirmed directly
   // const receipt = await cfx.sendRawTransaction(tx.serialize()).confirmed(); // await till confirmed directly

   console.log('receipt =>', receipt);
}

main().catch(e => console.error(e));
