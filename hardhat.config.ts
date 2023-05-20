import '@nomicfoundation/hardhat-toolbox'
import dotenv from 'dotenv'
import { HardhatUserConfig, task } from 'hardhat/config'
import 'hardhat-abi-exporter'

dotenv.config()

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners()

  for (const account of accounts) {
    console.log(account.address)
  }
})

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.17',
        settings: {
          optimizer: {
            enabled: true,
            runs: 888,
          },
        },
      },
    ],
  },
  paths: {
    artifacts: './src/contracts/artifacts',
    cache: './cache',
    sources: './src/contracts',
    tests: './src/test',
  },
  networks: {
    hardhat: {
      chainId: 1337,
      allowUnlimitedContractSize: false,
      from: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    },
    polygon_mumbai: {
      url: 'https://goerli.optimism.io',
      accounts: process.env.MUMBAI_KEY !== undefined ? [process.env.MUMBAI_KEY] : [],
    },
    polygon: {
      url: process.env.ROPSTEN_URL || '',
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    coinmarketcap: process.env.CMC_API_KEY,
    gasPrice: 1,
    currency: 'USD',
    src: './contracts',
  },
  abiExporter: {
    path: './abis',
    clear: true,
    runOnCompile: true,
    flat: true,
    only: [':Chinchiro$', ':DiceRoll$', ':DragonRules$'],
  },
  mocha: {
    timeout: 500000,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
}

export default config
