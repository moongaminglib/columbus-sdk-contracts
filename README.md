### sdk contracts

[English Docs](/en)

#### 描述
本项目为NFT铸造、空投、挖矿、盲盒售卖资源包,包括源码、脚本。并且基于NFT资产标准 [`ERC1155`](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1155.md)


#### 合作案例

| 名称 | 描述 |
| --- | --- |
| 烤仔NFT | 盲盒售卖 + 挖矿 |
| Condragon NFT | 盲盒售卖 + 挖矿 |
| Conhero NFT | 盲盒售卖 + 挖矿 |

---
#### 介绍

源码包括NFT创建、NFT空投、NFT盲盒售卖、NFT质押挖矿，还有testnet的执行脚本，在接下来会介绍使用方法。

通过该脚本铸造的NFT的，简单填写申请表，便可直通[Moongaming NFT平台](https://moonswap.fi/nft)，接入非常便捷。

- 示意图

![image](/assets/sdk_architecture.png)

- 合约介绍

| 名称 | 描述 |
| --- | --- |
| Genesis.sol | custom nft contrat |
| NFTBlindBox.sol | nft market Blind box |
| NFTStake.sol | nft stake Dig the dividend |

#### 环境准备

- npm
```
npm install
cp env-template.json env.json
vim env.json
```
替换 adminPrivateKey为部署合约账号的私钥，该账号需要有cfx。

- 编译

```
truffle compile
```

`testnet 表示测试网  tethys表示主网 注意env的配置`

#### 功能使用

##### 发行NFT

发行资产先了解ERC1155的标准，以及Meta信息
合约uri大多为NFT的元数据信息，json格式(包括名称、image、description, 各个属性标签)
meta 服务支持可以考虑使用 ipfs/中心化服务存储.

- 更换资产名称

```
# Genesis.sol
constructor( address _devAddr, string memory _baseMetadataURI)
    CRCN("any NFT", "xxNFT")
```

- 部署合约

```
node scripts/testnet/nft.deploy.js
```

- 铸造NFT

将上一步部署的合约地址填写在 contracts.json nft_addr后，并替换nft.create.js的 to地址

并且该脚本包括批量空投功能

```
node scripts/testnet/nft.create.js
```

##### 盲盒售卖

上架、定价

```
node scripts/testnet/blindbox.build.js
```

##### 质押挖矿

设置挖矿权重、分红速率

```
node scripts/testnet/stake.build.js
```
