const hre = require('hardhat'); // Hardhat Runtime Environment

async function main() {
  const MyGov = await hre.ethers.getContractFactory('MyGov');
  console.log('Deploying MyGOV Token...');
  const token = await MyGov.deploy('10000000');
  await token.deployed();
  console.log('MyGOV deployed to:', token.address);
}

// main().catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
