const { Conflux, format } = require("js-conflux-sdk");
let env = require('../../env.json');
let contracts = require('./contracts.json');
let assets = require('./assets.json');
let json_rpc_url = env.json_rpc;
let PRIVATE_KEY = env.adminPrivateKey;
let chainId = env.chainId;

const cfx = new Conflux({
    url: json_rpc_url,
    networkId: chainId,
    logger: console,
});
const sourceContract = require('../../build/contracts/NFTBlindBox.json');
const account = cfx.wallet.addPrivateKey(PRIVATE_KEY);
const contract = cfx.Contract({
    bytecode: sourceContract.bytecode,
    abi: sourceContract.abi,
});
async function main() {
    let nft = contracts.nft_addr;
    let devAddr = account.address;
    let FC = assets['FC'];
    let cMoon = assets['cMOON'];
    let fc_paths = [
        FC,
        cMoon
    ];
    let wCFX = assets['WCFX'];
    let wcfx_paths = [
        wCFX,
        assets['cUSDT'],
        assets['cETH'],
        cMoon
    ];
    let swap_route =  contracts['swapRouteV2'];
    let pool = account.address;

    const receipt = await contract.constructor(nft, devAddr, FC, fc_paths, cMoon, wCFX, wcfx_paths, swap_route, pool)
        .sendTransaction({ from: account, chainId })
        .executed();

    console.log("blindbox:", format.hexAddress(receipt.contractCreated))
}
main().catch(e => console.error(e));
