### sdk contracts

[中文文档](https://github.com/moongaminglib/columbus-sdk-contracts)

#### description

This project is a resource pack for NFT casting, airdrop, mining, and blind box sales, including source code and scripts。And based on the NFT asset standard [`ERC1155`](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1155.md)


#### Cooperation Case

| Name | Desc |
| --- | --- |
| Confi NFT | Blind box sale + NFT Stake |
| Condragon NFT | Blind box sale + NFT Stake |
| Conhero NFT | Blind box sale + NFT Stake |

---
#### Solution Introduction

Source code includes NFT creation, NFT airdrop, NFT blind box sales, NFT Stake，There are also testnet execution scripts，I will introduce how to use it next。

NFT cast by this script，Simply fill in the application form，Can pass through[Moongaming NFT](https://moonswap.fi/nft), use is very simple。

- Architecture

![image](/assets/sdk_architecture_en.png)

- Smart Contract introduction

| Name | Desc |
| --- | --- |
| Genesis.sol | custom nft contrat |
| NFTBlindBox.sol | nft market Blind box |
| NFTStake.sol | nft stake Dig the dividend |

#### Install

- npm
```
npm install
cp env-template.json env.json
vim env.json
```
Replece adminPrivateKey，and the account has cfx。

- Compile

```
truffle compile
```

`testnet is sandbox,  tethys is mainnet, focus env config`

#### Function Plugin

##### Create NFT

First understand the ERC1155 standard when issuing assets，And Metadata.
The smart contract uri is mostly NFT metadata information，For example, json format.
The metadata service can be supported by ipfs or centralized service storage support.

- Change NFT Info

```
# Genesis.sol
constructor( address _devAddr, string memory _baseMetadataURI)
    CRCN("any NFT", "xxNFT")
```

- Deploy Smart Contract

```
node scripts/testnet/nft.deploy.js
```

- Mint NFT

Fill in the contract address deployed in the previous step in contracts.json, replece nft_addr，then replace `to` variable  in nft.create.js file.

And the script includes batch airdrop function.

```
node scripts/testnet/nft.create.js
```

##### Blind box sale

Sale、set Price

```
node scripts/testnet/blindbox.build.js
```

##### NFT Stake

pool weight、token dividend speed

```
node scripts/testnet/stake.build.js
```
