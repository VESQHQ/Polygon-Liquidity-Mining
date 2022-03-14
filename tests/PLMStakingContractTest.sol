// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "hardhat/console.sol";

interface IPLMECR20 {
    function burnFrom(address account_, uint256 amount_) external;
}

// PLMStakingContractTest is the master of the WMATIC rewards and guardian of the PLM Deposits!.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract PLMStakingContractTest is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // The PLM TOKEN!
    address public immutable PLMToken;

    // For testing only
    IERC20 public immutable WMATIC;
    //IERC20 public constant WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    // For testing only
    uint256 public immutable epochTimeLength;
    //uint256 public constant epochTimeLength = 3600 * 24 * 30;

     // A counter variable to ensure we never withdraw too much WMATIC.
    uint256 public promisedWMATIC = 0;

    // permissions for certain address to be able to stake and harvest.
    mapping(address => bool) public whitelist;
    // a lifetime aggregate of how much PLM an account has ever staked here.
    mapping(address => uint256) public lifetimePLMStaked;

    // Info of each user.
    struct UserInfo {
        uint256 amount;               // How many PLM tokens the user has provided.
        uint256 WMATICRewardDebt;     // Reward debt.
        uint256 lastRewardTimestamp;  // Last time user staked/harvested
    }

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    // The block timestamp when normal WMATIC mining starts.
    uint256 public immutable startTime;

    event Deposit(address indexed user, uint256 amount);
    event RecoverMATIC(address indexed recipient, uint256 amount);
    event RecoverERC20Token(address indexed token, address indexed recipient, uint256 amount);
    event WhitelistEdit(address indexed participant, bool indexed included);

    constructor(
        IERC20 _WMATIC,
        address _PLMToken,
        /*uint256 _startTime,*/
        uint256 _epochTimeLength
    ) public {
        //require(block.timestamp < _startTime, "startTime must be in the future!");
        require(_PLMToken != address(0), "PLMToken parameter is address(0)");

        WMATIC = _WMATIC;
        PLMToken = _PLMToken;
        startTime = block.timestamp;
        epochTimeLength = _epochTimeLength;
    }

    // View function to see the end epoch time for a given unix timestamp.
    function getNextEpochStartTimeForTimestamp(uint256 unixTime) public view returns (uint256) {
        if (unixTime < startTime)
            return startTime;

        uint256 epochsSinceStartTime = (unixTime - startTime) / epochTimeLength;

        // Get the start time of the epoch the user last deposited in.
        uint256 epochStartTime = startTime + epochsSinceStartTime * epochTimeLength;
        uint256 epochEndTime = epochStartTime + epochTimeLength;

        return epochEndTime;
    }

    // View function to see number of expochs since the start of emissions.
    function numberOfEpochsSinceStart() external view returns (uint256) {
        if (block.timestamp < startTime)
            return 0;

        return (block.timestamp - startTime) / epochTimeLength;
    }

    // View function to see pending WMATICs on frontend.
    function pendingWMATIC(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];

        uint256 lastRewardTimestampOrStartTime = user.lastRewardTimestamp < startTime ? startTime : user.lastRewardTimestamp;

        // No rewards before or on start time.
        if (block.timestamp <= startTime)
            return 0;

        uint256 epochEndTime = getNextEpochStartTimeForTimestamp(lastRewardTimestampOrStartTime);
        uint256 epochStartTime = epochEndTime - epochTimeLength;

        uint256 currentOrEndOfEpochTime = block.timestamp > epochEndTime ? epochEndTime : block.timestamp;

        // If the epoch has ended, send them all of their due WMATIC to account for rounding errors.
        if (currentOrEndOfEpochTime == epochEndTime)
            return user.amount - user.WMATICRewardDebt;
        else
            return user.amount * (currentOrEndOfEpochTime - epochStartTime) / epochTimeLength  - user.WMATICRewardDebt;
    }

    // Deposit PLM tokens to this contract for WMATIC.
    function deposit(uint256 _amount) external nonReentrant {
        require(whitelist[msg.sender], "staker is not in the whitelist!");
        console.log("Deposit amount: %s", _amount);

        uint256 epochEnd = getNextEpochStartTimeForTimestamp(block.timestamp);
        uint256 epochStartTime = epochEnd - epochTimeLength;
        console.log("epoch from %s to %s", epochStartTime, epochEnd);
        console.log("_blockTime %s", block.timestamp);

        UserInfo storage user = userInfo[msg.sender];

        // Pay what is due from accumulated release (this epoch or previous).
        payPendingWMATIC();

        if (_amount > 0) {
            IPLMECR20(PLMToken).burnFrom(msg.sender, _amount);

            user.amount+= _amount;
            lifetimePLMStaked[msg.sender]+= _amount;

            // Add to the amount of WMATIC reserved for users.
            promisedWMATIC+= _amount;

            // Pay pro rata what was just deposited for the current epoch.
            payPendingWMATIC();
        }

        emit Deposit(msg.sender, _amount);
    }

    // Resets the users deposit accounting if we pass an epoch boundary.
    function resetUserDepositInfo() internal {
        UserInfo storage user = userInfo[msg.sender];

        uint256 lastRewardTimestampOrStartTime = user.lastRewardTimestamp < startTime ? startTime : user.lastRewardTimestamp;

        // Shouldn't attempt to reset if it's before startTime, or if we have deposited on this timestamp already.
        if (block.timestamp > lastRewardTimestampOrStartTime) {
            uint256 epochEndTime = getNextEpochStartTimeForTimestamp(lastRewardTimestampOrStartTime);

            // If we have passed one or more epoch boundaries we needed to reset before staking PLM.
            if (block.timestamp >= epochEndTime) {
                // Amount the user has deposited in an epoch should always equal the amount they have harvested for the epoch,
                // at the end of the epoch.
                assert(user.amount == user.WMATICRewardDebt);
                user.amount = 0;
                user.WMATICRewardDebt = 0;
            }
        }
    }

    // Pay pending WMATICs.
    function payPendingWMATIC() internal {
        console.log("payPendingWMATIC entered");
        UserInfo storage user = userInfo[msg.sender];

        uint256 WMATICPending = pendingWMATIC(msg.sender);

        if (WMATICPending > 0) {
            // If this fails the contract needs to be refilled with WMATIC before it can continue to function.
            require(WMATIC.balanceOf(address(this)) >= WMATICPending, "contract is being serviced, please wait.");
            // Send rewards
            WMATIC.safeTransfer(msg.sender, WMATICPending);

            // Update amount paid for this epoch
            user.WMATICRewardDebt+= WMATICPending;

            // Reduce the amount of WMATIC promised to the user.
            promisedWMATIC-= WMATICPending;

            console.log("WMATICPaid %s", WMATICPending);
        }

        resetUserDepositInfo();

        user.lastRewardTimestamp = block.timestamp;
    }

    // Recovery function for excess WMATIC
    function recoverWMATIC(address recipient, uint256 amount) external onlyOwner {
        require(recipient != address(0), "sending to 0 address");
        require(amount > 0, "can't recover 0 amounts");
        require(promisedWMATIC <= WMATIC.balanceOf(address(this)) - amount, "not enough WMATIC in contract");

        WMATIC.safeTransfer(recipient, amount);
        emit RecoverERC20Token(address(WMATIC), recipient, amount);
    }

    // Recovery function for excess WMATIC
    function recoverMATIC(address recipient) external onlyOwner {
        require(recipient != address(0), "sending to 0 address");

        uint256 maticBalance = address(this).balance;

        address(recipient).call{value: maticBalance}("");

        emit RecoverMATIC(recipient, maticBalance);
    }

    // Recovery function for lost tokens
    function recoverLostToken(address token, address recipient) external onlyOwner {
        require(token != address(WMATIC), "cannot recover WMATIC tokens here");
        require(recipient != address(0), "sending to 0 address");

        uint256 balance = IERC20(token).balanceOf(address(this));

        if (balance > 0) {
            IERC20(token).safeTransfer(recipient, balance);
            emit RecoverERC20Token(token, recipient, balance);
        }
    }

    function addToWhiteList(address participant, bool included) external onlyOwner {
        whitelist[participant] = included;

        emit WhitelistEdit(participant, included);
    }
}
