const Ohara_Protocol = artifacts.require('Ohara_Protocol');
const { prepareUpgrade } = require('@openzeppelin/truffle-upgrades');
 
module.exports = async function (deployer) {
  await prepareUpgrade('0x002932D67Fdd2327430Cd7688e602F70932Cb1e0', Ohara_Protocol, ['0xf465e4422BeC3FA5F29A55Aa76497Dda016b4131', 100], { deployer });
};