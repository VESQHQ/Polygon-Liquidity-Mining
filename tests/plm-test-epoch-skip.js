const { ethers } = require('hardhat');


async function main() {
  const [owner] = await ethers.getSigners();

  const PLMERC20 = await ethers.getContractFactory("PLMERC20Token");

  const plm = await PLMERC20.deploy()

  console.log("plm @ ", plm.address)

  const FakeWMATIC = await ethers.getContractFactory("FakeWMATIC");

  const wmatic = await FakeWMATIC.deploy()

  console.log("wmatic @ ", wmatic.address)

  const PLMEStakingContract = await ethers.getContractFactory("PLMStakingContractTest");

  const plmStaking = await PLMEStakingContract.deploy(wmatic.address, plm.address, '25')

  console.log("plmStaking @ ", plmStaking.address)

  await plmStaking.addToWhiteList(owner.address, true);

  await wmatic.transfer(plmStaking.address, '90000000')

  console.log("added owner to whitelist")

  await plm.setVault(owner.address)

  await plm.mint(owner.address, '90000000')

  await plm.approve(plmStaking.address, '90000000')

  console.log("approve spending of plm")

  await new Promise(resolve => setTimeout(resolve, 3 * 1000));

  console.log("plm balance before ", (await plm.balanceOf(owner.address)).toString())
  console.log("wmatic balance before ", (await wmatic.balanceOf(owner.address)).toString())

  await plmStaking.deposit('10000000')
  console.log("DEPOSIT!")

  console.log("plm balance  ", (await plm.balanceOf(owner.address)).toString())
  console.log("wmatic balance ", (await wmatic.balanceOf(owner.address)).toString())

  await new Promise(resolve => setTimeout(resolve, 1 * 1000));

  for (let i = 0;i<4;i++) {
    await plmStaking.deposit('0')

    console.log("plm balance  ", (await plm.balanceOf(owner.address)).toString())
    console.log("wmatic balance ", (await wmatic.balanceOf(owner.address)).toString())

    await new Promise(resolve => setTimeout(resolve, 1 * 1000));
  }

  await plmStaking.deposit('10000000')
  console.log("DEPOSIT!")

  await new Promise(resolve => setTimeout(resolve, 30 * 1000));

  await plmStaking.deposit('10000000')
  console.log("DEPOSIT!")

  for (let i = 0;i<8;i++) {
    await plmStaking.deposit('0')

    console.log("plm balance  ", (await plm.balanceOf(owner.address)).toString())
    console.log("wmatic balance ", (await wmatic.balanceOf(owner.address)).toString())

    await new Promise(resolve => setTimeout(resolve, 1 * 1000));
  }

  await plmStaking.deposit('10000000')
  console.log("DEPOSIT!")

  for (let i = 0;i<14;i++) {
    await plmStaking.deposit('0')

    console.log("plm balance  ", (await plm.balanceOf(owner.address)).toString())
    console.log("wmatic balance ", (await wmatic.balanceOf(owner.address)).toString())

    await new Promise(resolve => setTimeout(resolve, 1 * 1000));
  }
};

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
