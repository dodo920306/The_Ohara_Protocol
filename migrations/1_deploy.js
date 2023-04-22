const The_Ohara_Protocol = artifacts.require('The_Ohara_Protocol');
 
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
 
module.exports = async function (deployer) {
  await deployProxy(The_Ohara_Protocol, { deployer, initializer: 'initialize' });
};