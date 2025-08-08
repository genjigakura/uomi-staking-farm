// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract uomiFarm is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;          // total stake user
        uint256 rewardDebt;      // akuntansi reward
        uint256 lastDepositTime; // waktu deposit terakhir
        uint256 pendingReward;   // akrual reward pending (pre-mainnet)
    }

    struct PoolInfo {
        IERC20  token;           // token yang di-stake
        uint256 allocPoint;      // bobot alokasi reward
        uint256 lastRewardBlock; // blok terakhir dihitung
        uint256 accUomiPerShare; // akumulasi UOMI per share (1e18)
        uint256 totalStaked;     // total stake pool
        bool    mainnetReleased; // true jika mainnet dirilis (snapshot selesai)
    }

    // total alokasi semua pool
    uint256 public totalAllocPoint;
    // batas blok reward (setelah ini akrual berhenti)
    uint256 public maxRewardBlockNumber;
    // reward per blok (wei)
    uint256 public rewardPerBlock;

    uint256 public constant accUomiPerShareMultiple = 1e18;

    PoolInfo[] public poolInfo;
    mapping(uint256 pid => mapping(address user => UserInfo)) public userInfo;

    // events pengguna
    event Deposited(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed pid, uint256 amount);

    // events admin & info
    event PoolAdded(uint256 indexed pid, address token, uint256 allocPoint);
    event PoolUpdated(uint256 indexed pid, uint256 oldAllocPoint, uint256 newAllocPoint);
    event MainnetReleased(uint256 indexed pid);
    event MaxRewardBlockUpdated(uint256 oldVal, uint256 newVal);
    event RewardPerBlockUpdated(uint256 oldVal, uint256 newVal);
    event PendingClearedBeforeMainnet(address indexed user, uint256 indexed pid);

    // errors
    error NotEnoughToWithdraw();
    error AllocPointZero();
    error DepositZero();
    error WithdrawZero();
    error PoolNotExist();
    error StakingPeriodEnded();
    error ZeroAddressToken();

    function initialize(
        uint256 _rewardPerBlock,
        uint256 _maxRewardBlockNumber
    ) external initializer {
        rewardPerBlock = _rewardPerBlock;
        maxRewardBlockNumber = _maxRewardBlockNumber;
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
    }

    // ---------- internal util ----------
    function _assertValidPid(uint256 _pid) internal view {
        if (_pid >= poolInfo.length) revert PoolNotExist();
    }
    // -----------------------------------

    // ======== View helpers ========

    function getTotalRewardByPoolId(
        uint256 _pid,
        address _address
    ) public view returns (uint256) {
        _assertValidPid(_pid);
        UserInfo storage user = userInfo[_pid][_address];
        uint256 poolRewardPerShare = getPoolRewardPerShare(_pid);
        uint256 totalReward = ((user.amount * poolRewardPerShare) / accUomiPerShareMultiple) - user.rewardDebt;
        return totalReward + user.pendingReward;
    }

    function getTotalReward(address _address) public view returns (uint256) {
        uint256 totalReward = 0;
        uint256 length = poolInfo.length;

        for (uint256 pid = 0; pid < length; ++pid) {
            UserInfo storage user = userInfo[pid][_address];
            uint256 poolRewardPerShare = getPoolRewardPerShare(pid);
            totalReward =
                totalReward +
                ((user.amount * poolRewardPerShare) / accUomiPerShareMultiple) -
                user.rewardDebt + user.pendingReward;
        }
        return totalReward;
    }

    function poolLength() external view returns (uint256) { return poolInfo.length; }

    // ======== Admin ========

    function updateMaxRewardBlockNumber(uint256 _new) public onlyOwner {
        uint256 old = maxRewardBlockNumber;
        maxRewardBlockNumber = _new;
        emit MaxRewardBlockUpdated(old, _new);
    }

    function updateRewardPerBlock(uint256 _new) public onlyOwner {
        uint256 old = rewardPerBlock;
        rewardPerBlock = _new;
        emit RewardPerBlockUpdated(old, _new);
    }

    function setMainnetReleased(uint256 _pid) public onlyOwner {
        _assertValidPid(_pid);
        poolInfo[_pid].mainnetReleased = true;
        emit MainnetReleased(_pid);
    }

    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate
    ) public onlyOwner {
        if (_allocPoint < 1) revert AllocPointZero();
        if (address(_token) == address(0)) revert ZeroAddressToken();

        if (_withUpdate) massUpdatePools();

        totalAllocPoint = totalAllocPoint + _allocPoint;

        poolInfo.push(
            PoolInfo({
                token: _token,
                allocPoint: _allocPoint,
                lastRewardBlock: block.number,
                accUomiPerShare: 0,
                totalStaked: 0,
                mainnetReleased: false
            })
        );

        emit PoolAdded(poolInfo.length - 1, address(_token), _allocPoint);
    }

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        _assertValidPid(_pid);
        if (_withUpdate) massUpdatePools();

        uint256 old = poolInfo[_pid].allocPoint;
        totalAllocPoint = totalAllocPoint - old + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;

        emit PoolUpdated(_pid, old, _allocPoint);
    }

    // ======== Reward update ========

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) updatePool(pid);
    }

    function updatePool(uint256 _pid) public {
        _assertValidPid(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        pool.accUomiPerShare = getPoolRewardPerShare(_pid);
        pool.lastRewardBlock = block.number;
    }

    // ======== User actions ========

    function depositForUser(uint256 _pid, uint256 _amount, address _user) public nonReentrant {
        if (_amount == 0) revert DepositZero();
        if (block.number >= maxRewardBlockNumber) revert StakingPeriodEnded();

        _assertValidPid(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.mainnetReleased) revert StakingPeriodEnded();

        UserInfo storage user = userInfo[_pid][_user];
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = ((user.amount * pool.accUomiPerShare) / accUomiPerShareMultiple) - user.rewardDebt;
            if (pending > 0) user.pendingReward = user.pendingReward + pending;
        }

        pool.token.safeTransferFrom(_user, address(this), _amount);
        user.amount += _amount;
        pool.totalStaked += _amount;

        user.rewardDebt = (user.amount * pool.accUomiPerShare) / accUomiPerShareMultiple;
        user.lastDepositTime = block.timestamp;

        emit Deposited(_user, _pid, _amount);
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        depositForUser(_pid, _amount, msg.sender);
    }

    function withdrawAll(uint256 _pid) public {
        _assertValidPid(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        withdraw(_pid, amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        _assertValidPid(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount < _amount) revert NotEnoughToWithdraw();
        if (_amount == 0) revert WithdrawZero();

        updatePool(_pid);

        if (!pool.mainnetReleased) {
            user.lastDepositTime = block.timestamp;
            if (user.pendingReward > 0) emit PendingClearedBeforeMainnet(msg.sender, _pid);
            user.pendingReward = 0;
        }

        user.amount -= _amount;
        if (user.amount == 0) user.lastDepositTime = 0;

        pool.token.safeTransfer(msg.sender, _amount);
        pool.totalStaked -= _amount;

        user.rewardDebt = (user.amount * pool.accUomiPerShare) / accUomiPerShareMultiple;

        emit Withdrawn(msg.sender, _pid, _amount);
    }

    // ======== Internal reward math ========

    function getPoolRewardPerShare(uint256 _pid) internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        if (block.number < pool.lastRewardBlock) {
            return pool.accUomiPerShare;
        }

        uint256 tokenSupply = pool.totalStaked;
        if (tokenSupply == 0) {
            return pool.accUomiPerShare;
        }

        // guard alokasi
        if (totalAllocPoint == 0 || pool.allocPoint == 0) {
            return pool.accUomiPerShare;
        }

        if (pool.lastRewardBlock > maxRewardBlockNumber) {
            return pool.accUomiPerShare;
        }

        uint256 currentRewardBlock = block.number >= maxRewardBlockNumber
            ? maxRewardBlockNumber
            : block.number;

        uint256 totalReward = (currentRewardBlock - pool.lastRewardBlock) * rewardPerBlock;
        uint256 uomiReward = (totalReward * pool.allocPoint) / totalAllocPoint;

        return pool.accUomiPerShare + ((uomiReward * accUomiPerShareMultiple) / tokenSupply);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

