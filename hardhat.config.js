require("@nomiclabs/hardhat-ethers");
const nets = require('./network.json');

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: nets,
  defaultNetwork: "hardhat"
};