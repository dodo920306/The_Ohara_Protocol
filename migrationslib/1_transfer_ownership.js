const { admin } = require('@openzeppelin/truffle-upgrades');
 
module.exports = async function (deployer) {
  // Use address of your Gnosis Safe
  const gnosisSafe = '0xf465e4422BeC3FA5F29A55Aa76497Dda016b4131';
 
  await admin.transferProxyAdminOwnership(gnosisSafe);
};