const Ohara_Protocol = artifacts.require('Ohara_Protocol');
 
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
 
module.exports = async function (deployer) {
  await deployProxy(Ohara_Protocol, ['0xf465e4422BeC3FA5F29A55Aa76497Dda016b4131', 1000], { deployer, initializer: 'initialize' });
};