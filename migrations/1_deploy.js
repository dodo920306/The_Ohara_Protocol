const Market = artifacts.require('Market');
const The_Ohara_Protocol = artifacts.require('The_Ohara_Protocol');

//const { deployProxy } = require('@openzeppelin/truffle-upgrades');
 
module.exports = async function (deployer) {
  
  await deployer.deploy(Market);
  await deployer.deploy(The_Ohara_Protocol, Market.address );
  //await deployProxy(The_Ohara_Protocol, { deployer, initializer: 'initialize' });
};