const The_Ohara_Protocol = artifacts.require('The_Ohara_Protocol');
const { prepareUpgrade } = require('@openzeppelin/truffle-upgrades');
 
module.exports = async function (deployer) {
  await prepareUpgrade('0x8467632F13fAB0feAC7C715836b4cf415a9A7Ba3', The_Ohara_Protocol, { deployer });
};