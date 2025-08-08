const { expect } = require("chai");
const { ethers } = require("hardhat");
const toWei = (n) => ethers.utils.parseEther(n);

describe("uomiFarm — core flows & guards", function () {
  let owner, alice, bob, token, farm;

  beforeEach(async () => {
    [owner, alice, bob] = await ethers.getSigners();

    const MockToken = await ethers.getContractFactory("MockToken");
    token = await MockToken.deploy("UOMI", "UOMI", 18);
    await token.deployed();

    const Farm = await ethers.getContractFactory("uomiFarm");
    farm = await Farm.deploy();
    await farm.deployed();

    const currentBlock = await ethers.provider.getBlockNumber();
    await farm.initialize(
      toWei("1"),          // rewardPerBlock
      currentBlock + 1000  // maxRewardBlockNumber
    );

    await token.mint(alice.address, toWei("1000"));
    await token.mint(bob.address,   toWei("1000"));
    await token.connect(alice).approve(farm.address, toWei("1000"));
    await token.connect(bob).approve(farm.address,   toWei("1000"));

    await expect(farm.connect(owner).add(100, token.address, false))
      .to.emit(farm, "PoolAdded");
  });

  it("guards invalid pid with PoolNotExist", async () => {
    await expect(farm.connect(alice).deposit(999, toWei("1")))
      .to.be.revertedWithCustomError(farm, "PoolNotExist");
    await expect(farm.connect(alice).withdraw(999, toWei("1")))
      .to.be.revertedWithCustomError(farm, "PoolNotExist");
    await expect(farm.updatePool(999))
      .to.be.revertedWithCustomError(farm, "PoolNotExist");
  });

  it("reverts on zero deposit and zero withdraw", async () => {
    await expect(farm.connect(alice).deposit(0, 0))
      .to.be.revertedWithCustomError(farm, "DepositZero");
    await expect(farm.connect(alice).withdraw(0, 0))
      .to.be.revertedWithCustomError(farm, "WithdrawZero");
  });

  it("deposits, withdraws, emits events, and keeps accounting", async () => {
    await expect(farm.connect(alice).deposit(0, toWei("100")))
      .to.emit(farm, "Deposited").withArgs(alice.address, 0, toWei("100"));

    await expect(farm.connect(alice).withdraw(0, toWei("40")))
      .to.emit(farm, "Withdrawn").withArgs(alice.address, 0, toWei("40"));
  });

  it("resets pending reward on withdraw before mainnet release (with event)", async () => {
    await farm.connect(alice).deposit(0, toWei("50"));
    for (let i = 0; i < 5; i++) await ethers.provider.send("evm_mine", []);

    const before = await farm.getTotalRewardByPoolId(0, alice.address);
    expect(before).to.gt(0);

    await expect(farm.connect(alice).withdraw(0, toWei("10")))
      .to.emit(farm, "PendingClearedBeforeMainnet");

    const after = await farm.getTotalRewardByPoolId(0, alice.address);
    expect(after).to.equal(0);
  });

  it("admin events fire", async () => {
    await expect(farm.connect(owner).set(0, 200, true))
      .to.emit(farm, "PoolUpdated");
    await expect(farm.connect(owner).updateRewardPerBlock(toWei("2")))
      .to.emit(farm, "RewardPerBlockUpdated");
    const block = (await ethers.provider.getBlockNumber()) + 500;
    await expect(farm.connect(owner).updateMaxRewardBlockNumber(block))
      .to.emit(farm, "MaxRewardBlockUpdated");
    await expect(farm.connect(owner).setMainnetReleased(0))
      .to.emit(farm, "MainnetReleased");
  });
});

