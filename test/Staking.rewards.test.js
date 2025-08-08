const { expect } = require("chai");
const { ethers } = require("hardhat");
const toWei = (n) => ethers.utils.parseEther(n);

describe("uomiFarm — rewards cap & alloc guards", function () {
  let owner, user, token, farm;

  beforeEach(async () => {
    [owner, user] = await ethers.getSigners();

    const MockToken = await ethers.getContractFactory("MockToken");
    token = await MockToken.deploy("UOMI", "UOMI", 18);
    await token.deployed();

    const Farm = await ethers.getContractFactory("uomiFarm");
    farm = await Farm.deploy();
    await farm.deployed();

    const current = await ethers.provider.getBlockNumber();
    await farm.initialize(
      toWei("1"),     // rewardPerBlock
      current + 30    // stop soon for test
    );

    await token.mint(user.address, toWei("1000"));
    await token.connect(user).approve(farm.address, toWei("1000"));

    await farm.connect(owner).add(100, token.address, false);
  });

  it("stops accruing after maxRewardBlockNumber", async () => {
    await farm.connect(user).deposit(0, toWei("100"));
    for (let i = 0; i < 60; i++) await ethers.provider.send("evm_mine", []);
    const snap = await farm.getTotalRewardByPoolId(0, user.address);

    for (let i = 0; i < 20; i++) await ethers.provider.send("evm_mine", []);
    const after = await farm.getTotalRewardByPoolId(0, user.address);
    expect(after).to.equal(snap);
  });

  it("guards totalAllocPoint == 0 (no div-by-zero in updatePool)", async () => {
    await farm.connect(user).deposit(0, toWei("10"));
    await farm.connect(owner).set(0, 0, true); // totalAllocPoint == 0
    await expect(farm.updatePool(0)).to.not.be.reverted;
  });

  it("rejects deposit after staking period ends", async () => {
    for (let i = 0; i < 50; i++) await ethers.provider.send("evm_mine", []);
    await expect(farm.connect(user).deposit(0, toWei("1")))
      .to.be.revertedWithCustomError(farm, "StakingPeriodEnded");
  });
});

