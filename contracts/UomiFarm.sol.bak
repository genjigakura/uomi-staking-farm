//
//
//       ██╗░░░██╗░█████╗░███╗░░░███╗██╗
//       ██║░░░██║██╔══██╗████╗░████║██║
//       ██║░░░██║██║░░██║██╔████╔██║██║
//       ██║░░░██║██║░░██║██║╚██╔╝██║██║
//       ╚██████╔╝╚█████╔╝██║░╚═╝░██║██║
//       ░╚═════╝░░╚════╝░╚═╝░░░░░╚═╝╚═╝
//
//       Staking farm contract for Uomi token
//
//
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract uomiFarm is UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount; // How many  tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 lastDepositTime; // Last deposit time
        uint256 pendingReward; // Pending reward
        //
        // We do some fancy math here. Basically, any point in time, the amount of Uomi
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (userInfo.amount * pool.accUomiPerShare) - userInfo.rewardDebt
        //
        // Whenever a user deposits or withdraws tokens to a pool. Here's what happens:
        //   1. The pool's accUomiPerShare (and lastRewardBlock) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's amount gets updated.
        //   4. User's rewardDebt gets updated.
    }

    struct PoolInfo {
        IERC20 token; // Address of staked token
        uint256 allocPoint; // How many allocation points assigned to this pool. 
        uint256 lastRewardBlock; // Last block number that Uomi distribution occurs.
        uint256 accUomiPerShare; // Accumulated Uomi per share, times 1e18. See below.
        uint256 totalStaked; // Total staked in this pool
        bool mainnetReleased; // true if the mainnet has been released
    }

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when uomi mining starts ->

    // max reward block
    uint256 public maxRewardBlockNumber;

    // rewad per block in wei
    uint256 public rewardPerBlock;

    // Accumulated uomi per share, times 1e18.
    uint256 public constant accUomiPerShareMultiple = 1e18;

    // Info on each pool added
    PoolInfo[] public poolInfo;
    // Info of each user that stakes tokens.
    mapping(uint256 pid => mapping(address user => UserInfo)) public userInfo;
    //events
    event Deposited(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed pid, uint256 amount);
    //errors
    error NotEnoughToWithdraw();
    error AllocPointZero();
    error MaxPoolCapReached();
    error DepositZero();
    error WithdrawZero();
    error PoolNotExist();
    error StakingPeriodEnded();

    function initialize(
        uint256 _rewardPerBlock,
        uint256 _maxRewardBlockNumber
    ) external initializer {
        rewardPerBlock = _rewardPerBlock;
        maxRewardBlockNumber = _maxRewardBlockNumber;
        __Ownable_init(msg.sender);
    }

    /**
     * @dev Returns the total reward for a user in a specific pool.
     * @param _pid The pool ID.
     * @param _address The user's address.
     * @return The total reward for the user in the specified pool.
     */
    function getTotalRewardByPoolId(
        uint256 _pid,
        address _address
    ) public view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_address];

        uint256 poolRewardPerShare = getPoolRewardPerShare(_pid);
        uint256 totalReward = ((user.amount * poolRewardPerShare) /
            accUomiPerShareMultiple) - user.rewardDebt;

        return totalReward + user.pendingReward;
    }

    /**
     * @dev Returns the total reward for a user in all pools.
     * @param _address The user's address.
     * @return The total reward for the user in all pools.
     */
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

    /**
     * @dev Returns the number of pools in the UomiFarm contract.
     * @return The length of the poolInfo array.
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @dev Updates the maximum reward block number.
     * @param _newMaxRewardBlockNumber The new maximum reward block number.
     * Only the contract owner can call this function.
     */
    function updateMaxRewardBlockNumber(
        uint256 _newMaxRewardBlockNumber
    ) public onlyOwner {
        maxRewardBlockNumber = _newMaxRewardBlockNumber;
    }

    /**
     * @dev Updates the reward per block for staking.
     * @param _rewardPerBlock The new reward per block value.
     * Only the contract owner can call this function.
     */
    function updateRewardPerBlock(uint256 _rewardPerBlock) public onlyOwner {
        rewardPerBlock = _rewardPerBlock;
    }

    /**
     * @notice Marks mainnet released.
     * @dev This function can only be called by the owner.
     * @param _pid The ID of the pool to be marked as released.
     */
    function setMainnetReleased(uint256 _pid) public onlyOwner {
        poolInfo[_pid].mainnetReleased = true;
    }


    /**
     * @dev Adds a new pool to the UomiFarm contract.
     * @param _allocPoint The allocation point of the pool.
     * @param _token The address of the staked token.
     * @param _withUpdate Whether to update all pools before adding the new one.
     * @notice Only the contract owner can call this function.
     */
    function add(
        uint256 _allocPoint, // allocation point for the pool
        IERC20 _token, // staked token address
        bool _withUpdate //update all pools
    ) public onlyOwner {
        if (_allocPoint < 1) {
            revert AllocPointZero();
        }

        if (_withUpdate) {
            massUpdatePools();
        }
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
    }

    /**
     * @dev Updates the allocation point and other parameters of a pool.
     * @param _pid The pool ID.
     * @param _allocPoint The new allocation point for the pool.
     * @param _withUpdate Whether to update all pools before making the change.
     *                    Set to true if there are pending changes in other pools.
     *                    Set to false if only updating a single pool.
     * @notice Only the contract owner can call this function.
     */
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint =
            totalAllocPoint -
            poolInfo[_pid].allocPoint +
            _allocPoint;

        poolInfo[_pid].allocPoint = _allocPoint;
    }

    /**
     * @dev Updates all pools in the UomiFarm contract.
     * This function iterates through all the pools and calls the `updatePool` function for each pool.
     * It is a public function that can be called by anyone.
     */
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /**
     * @dev Updates the pool information and calculates the accumulated UOMI rewards per share.
     * @param _pid The pool ID.
     * @notice This function should be called periodically to update the pool rewards.
     */
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        pool.accUomiPerShare = getPoolRewardPerShare(_pid);
        pool.lastRewardBlock = block.number;
    }


    /**
     * @dev Allows a user to deposit tokens into a specific pool.
     * @param _pid The pool ID.
     * @param _amount The amount of tokens to deposit.
     * Requirements:
     * - The amount must be greater than zero.
     * - The pool must exist.
     * Effects:
     * - Updates the pool information.
     * - Transfers the deposited tokens from the user to the contract.
     * - Updates the user's staked amount and the pool's total staked amount.
     * - Calculates and transfers any pending rewards to the user.
     * - Updates the user's reward debt.
     * - Updates the user's last deposit time.
     * Emits a `Deposited` event.
     */
    function depositForUser(uint256 _pid, uint256 _amount, address _user) public {
        if (_amount == 0) revert DepositZero();
        if (block.number >= maxRewardBlockNumber) revert StakingPeriodEnded();

        PoolInfo storage pool = poolInfo[_pid];
        if (pool.token == IERC20(address(0))) revert PoolNotExist();
        if (pool.mainnetReleased) revert StakingPeriodEnded();

        UserInfo storage user = userInfo[_pid][_user];
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = ((user.amount * pool.accUomiPerShare) /
                accUomiPerShareMultiple) - user.rewardDebt;

            if (pending > 0) {
                user.pendingReward = user.pendingReward + pending;
            }
        }

        pool.token.safeTransferFrom(_user, address(this), _amount);
        user.amount = user.amount + _amount;
        pool.totalStaked = pool.totalStaked + _amount;

        user.rewardDebt =
            (user.amount * pool.accUomiPerShare) /
            accUomiPerShareMultiple;
        user.lastDepositTime = block.timestamp;
        emit Deposited(_user, _pid, _amount);
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        depositForUser(_pid, _amount, msg.sender);
    }

    /**
     * @dev Allows a user to withdraw all their staked tokens from a specific pool.
     * @param _pid The pool ID.
     */
    function withdrawAll(uint256 _pid) public {
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        withdraw(_pid, amount);
    }

    /**
     * @dev Allows a user to withdraw their staked tokens from a specific pool.
     * @param _pid The pool ID.
     * @param _amount The amount of tokens to withdraw.
     * @notice The user must have enough tokens staked to withdraw the specified amount.
     * @notice If the user has not reached the minimum staking time for the pool, the withdrawal will be rejected.
     * @notice The user will receive any pending rewards before withdrawing their tokens.
     * @notice The user's staked token balance and the pool's total staked tokens will be updated accordingly.
     * @notice Emits a `Withdrawn` event with the user's address, pool ID, and amount of tokens withdrawn.
     */
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount < _amount) revert NotEnoughToWithdraw();
        if (_amount == 0) revert WithdrawZero();
        

        updatePool(_pid);

        if (!pool.mainnetReleased) {
            user.lastDepositTime = block.timestamp;
            user.pendingReward = 0;
        } 

      
        user.amount = user.amount - _amount;
        if(user.amount == 0){
            user.lastDepositTime = 0;
        }
        pool.token.safeTransfer(msg.sender, _amount);
        pool.totalStaked = pool.totalStaked - _amount;
    

        user.rewardDebt =
            (user.amount * pool.accUomiPerShare) /
            accUomiPerShareMultiple;

        emit Withdrawn(msg.sender, _pid, _amount);
    }

    /**
     * @dev Calculates the reward per share for a given pool.
     * @param _pid The pool ID.
     * @return The reward per share for the pool.
     */
    function getPoolRewardPerShare(
        uint256 _pid
    ) internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number < pool.lastRewardBlock) {
            return 0;
        }
        uint256 tokenSupply = pool.totalStaked;
        if (tokenSupply == 0) {
            return 0;
        }
        if (pool.lastRewardBlock > maxRewardBlockNumber) {
            return pool.accUomiPerShare;
        }

        uint256 currentRewardBlock = block.number >= maxRewardBlockNumber
            ? maxRewardBlockNumber
            : block.number;

        uint256 totalReward = (currentRewardBlock - pool.lastRewardBlock) *
            rewardPerBlock;

        uint256 uomiReward = (totalReward * pool.allocPoint) / totalAllocPoint;

        return
            pool.accUomiPerShare +
            ((uomiReward * accUomiPerShareMultiple) / tokenSupply);
    }

    function _authorizeUpgrade(address)
        internal
        override
        onlyOwner
    {}

}