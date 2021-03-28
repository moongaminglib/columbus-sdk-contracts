const { Conflux, util, format } = require('js-conflux-sdk');
const ethers = require('ethers');

let env = require('../../env.json');
let contracts = require('./contracts.json');
let json_rpc_url = env.json_rpc;
let PRIVATE_KEY = env.adminPrivateKey;

let chainId = env.chainId;

const cfx = new Conflux({
  url: json_rpc_url,
  networkId: chainId
});

const sourceContract = require('../../build/contracts/Genesis.json');
const account = cfx.Account(PRIVATE_KEY);
let from = account.address;
console.log('from =>', from);

let contract_address = contracts.nft_addr;

const contract = cfx.Contract({
  abi: sourceContract.abi,
  address: contract_address,
});

async function main() {

    let tokenId = 1;

    let to = contracts.nft_stake_addr;
    // await nftStake(to, tokenId);

    // let to = from;
    // await nftTranser(to, tokenId);
}

// NFT Stake
async function nftStake(to, tokenId)
{
  console.log('nftStake =>', to, tokenId);

  let tokenId = 1;
  let amount = 1;
  // x参数描述: 01 + placeId(32位)
  let x = Buffer.from('010000000000000000000000000000000000000000000000000000000000000010', 'hex');
  let estimate = await contract.safeTransferFrom(from, to, tokenId, amount, x).estimateGasAndCollateral({from: from});
  let data = contract.safeTransferFrom(from, to, tokenId, amount, x).data;

  await packTransaction(estimate, data);
}

async function nftTransfer(to, tokenId)
{
  console.log('nftTranser =>', to, tokenId);
  let estimate = await contract.safeTransferFrom(from, to, tokenId, 1, Buffer.from('', 'hex')).estimateGasAndCollateral({from: from});
  let data = await contract.safeTransferFrom(from, to, tokenId, 1, Buffer.from('', 'hex')).data;

  //function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount, bytes calldata _data)
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
