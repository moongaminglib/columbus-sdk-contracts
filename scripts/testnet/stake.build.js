const { Conflux, util, format } = require('js-conflux-sdk');

let env = require('../../env.json');
let contracts = require('./contracts.json');
let assets = require('./assets.json');

let json_rpc_url = env.json_rpc;
let PRIVATE_KEY = env.adminPrivateKey;

let chainId = env.chainId;

const cfx = new Conflux({
  url: json_rpc_url,
  networkId: chainId
});

const sourceContract = require('../../build/contracts/NFTStake.json');
const account = cfx.wallet.addPrivateKey(PRIVATE_KEY);
let from = account.address;

let contract_address = contracts.nft_stake_addr;

const contract = cfx.Contract({
  abi: sourceContract.abi,
  address: contract_address,
});

async function main() {

  let _cfxBalance = await cfx.getBalance(from);
  console.log('cfxBalance =>', _cfxBalance.toString() / 10 ** 18);
  // await setLockRates();

  // let placeId = 3;
  // await unlockPlace(placeId);

  //
  // let placeId = 1;
  // await unstakeNft(placeId);

  // let devAddr = '';
  // await setDevAddr(devAddr);

  let _apyRatio = 20;
  await setApyRatio(_apyRatio);
}

async function setApyRatio(apyRatio)
{
  console.log('setApyRatio =>', apyRatio);
  // check
  let estimate = await contract.setApyRatio(apyRatio).estimateGasAndCollateral({from: from});
  let data = await contract.setApyRatio(apyRatio).data;

  await packTransaction(estimate, data);
}

async function setDevAddr(devAddr)
{
  console.log('setDevAddr =>', devAddr);
  // check
  let estimate = await contract.setDevAddr(devAddr).estimateGasAndCollateral({from: from});
  let data = await contract.setDevAddr(devAddr).data;

  await packTransaction(estimate, data);
}

async function unstakeNft(placeId)
{
  console.log('unstakeNft=>', placeId);

  // check
  let estimate = await contract.unstake(placeId).estimateGasAndCollateral({from: from});
  let data = await contract.unstake(placeId).data;

  await packTransaction(estimate, data);
}

async function unlockPlace(placeId)
{
  console.log('unlockPlace=>', placeId);

  // check
  let estimate = await contract.unlockPlace(placeId).estimateGasAndCollateral({from: from});
  let data = await contract.unlockPlace(placeId).data;

  await packTransaction(estimate, data);
}

async function setLockRates()
{
   // let prices = [100 * 1e18, 300 * 1e18, 800 * 1e18, 1500 * 1e18];
   //let prices = [1 * 1e18, 5 * 1e18, 10 * 1e18, 23 * 1e18];
   //let rates = [2, 4, 8, 16];

   let prices = [1 * 1e18, 5 * 1e18];
   let rates = [2, 4];

   console.log('setLockRates =>', prices, rates);

  // check
  let estimate = await contract.setLockRates(prices, rates).estimateGasAndCollateral({from: from});
  let data = await contract.setLockRates(prices, rates).data;

  await packTransaction(estimate, data);
}

async function setNftRates(catId, levels, rates)
{
   console.log('setNftRates =>', catIds, levels, rates);

   // check
   let estimate = await contract.setNFTRates(catId, levels, rates).estimateGasAndCollateral({from: from});
   let data = await contract.setNFTRates(catId, levels, rates).data;

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

   const receipt = await cfx.sendRawTransaction(tx.serialize()).executed(); // await till executed directly
   // const receipt = await cfx.sendRawTransaction(tx.serialize()).confirmed(); // await till confirmed directly

   console.log('receipt =>', receipt);
}


main().catch(e => console.error(e));
