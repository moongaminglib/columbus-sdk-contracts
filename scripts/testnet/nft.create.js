const { Conflux, util, address, format } = require('js-conflux-sdk');

let env = require('../../env.json');
let contracts = require('./contracts.json');
let json_rpc_url = env.json_rpc;
let PRIVATE_KEY = env.adminPrivateKey;
let chainId = env.chainId;

const cfx = new Conflux({
  url: json_rpc_url,
  networkId: env['chainId']
});

const sourceContract = require('../../build/contracts/Genesis.json');
const account = cfx.wallet.addPrivateKey(PRIVATE_KEY);
let from = account.address;

let contract_address = contracts.nft_addr;
const contract = cfx.Contract({
  abi: sourceContract.abi,
  address: contract_address,
});

async function main() {
  // Batch Airdrop NFT
  // await batchCreate();
  // create NFT
  await singleCreate();
}

async function ownersOf(_id)
{
  let addreses = await contract.ownerOf(_id).call();

  console.log(addreses, _id);
}


async function batchCreate()
{
  let users = require('./users.json');

  console.log('length =>', users.length);
  let sub_users = [];
  let sub_uris = [];
  let totalCount = 0;
  let _startTokenId = 1;  // start tokenid warn retry
  let batchSize = 10;
  let _start = _startTokenId - 1;
  for(var i = _start; i< users.length; i ++) {
    let _user = users[i];
    let _address = _user.address;
    let _uri = '/' + _user.uri;
    if(sub_users.length == batchSize){
      totalCount += sub_users.length;
      console.log(sub_users);
      console.log(sub_users[0], "startTokenId=>", _startTokenId);
      let _exists = await isTokenOwner(sub_users[0], _startTokenId);
      if(!_exists){
        _exists = await checkIdUsed(_startTokenId);
      }

      if(_exists){
         console.log('tokenid exists =>', _startTokenId, _startTokenId + 10);
         return;
      }

      await batchCreateChain(sub_users, sub_uris);
      _startTokenId += batchSize;
      sub_users = [];
      sub_uris = [];
    }

    sub_users.push(_address);
    sub_uris.push(_uri);

  }

  await batchCreateChain(sub_users, sub_uris);
}

async function batchCreateChain(sub_users, sub_uris)
{
    // check
    let x = Buffer.from('', 'hex')
    let estimate = await contract.batchCreateNFT(sub_users, sub_uris, x).estimateGasAndCollateral({from: from});
    let data = await contract.batchCreateNFT(sub_users, sub_uris, x).data;

    await packTransaction(estimate, data);
}

async function isTokenOwner(owner, id)
{

    let isExists = await contract.isTokenOwner(owner, id).call();

    return isExists;
}

async function checkIdUsed(id)
{
    let _owner = await contract.creators(id);

    return format.hexAddress(_owner) != 0x0000000000000000000000000000000000000000;
}

async function singleCreate()
{
    console.log('singleCreate =>');
    let user = '0x1c3a62D6F6bFe0570AaFa9c9e18b1c089c865820'; //hex address
    let uri = '/1111.json';

    let x = Buffer.from('', 'hex')
    let estimate = await contract.createNFT(user, uri, x).estimateGasAndCollateral({from: from});
    let data = await contract.createNFT(user, uri, x).data;

    await packTransaction(estimate, data);
}


async function packTransaction(estimate, transData, value = 0)
{
   // check
   let data = transData;
   let _from = account.address;
   let nonce = await cfx.getNextNonce(_from);
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
