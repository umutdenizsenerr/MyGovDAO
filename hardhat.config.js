require('@nomicfoundation/hardhat-toolbox');
require('hardhat-gas-reporter');
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      accounts: {
        mnemonic: 'test test test test test test test test test test test junk',
        path: "m/44'/60'/0'/0",
        initialIndex: 0,
        count: 550,
        passphrase: '',
      },
    },
  },
  gasReporter: {
    currency: 'CHF',
    gasPrice: 21,
    enabled: true,
  },

  solidity: {
    version: '0.8.17',
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
};
