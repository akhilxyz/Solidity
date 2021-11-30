//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./interfaces/IMasterChef.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract Charity is Ownable, Initializable{
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    
    IMasterChef public masterchef;
    uint256 public pid;
    IBEP20 public stakeToken;
    IBEP20 public rewardToken;
    
    // uint256 public totalAmount;
    // uint256 public totalRewards;
    bool public stakingPhase;
    // bool public stakingPhaseStop;
    uint256 public charityRound;
    uint256 public maxDeposit;
    
    address[] public projects; 
    //charityRound => totalAmount
    mapping(uint256 => uint256) public totalAmount;
    //charityRound => totalRewards
    mapping(uint256 => uint256) public totalRewards;
    //project => amount staked in project
    mapping(address => uint256) public depositAmount;
    //project => staking allowed
    // mapping(address => bool) public depositAllow;
    //user => charityRound => amount staked by user
    mapping(address => mapping(uint256 => uint256)) public userAmount;
    
    constructor () {}
    
    function initialize(
        IMasterChef _masterchef,
        uint256 _pid,
        IBEP20 _stakeToken,
        IBEP20 _rewardToken,
        uint256 _maxdeposit
    ) public initializer{
        masterchef = _masterchef;
        pid = _pid;
        stakeToken = _stakeToken; 
        rewardToken = _rewardToken;
        maxDeposit = _maxdeposit;
        IBEP20(_stakeToken).approve(address(_masterchef), (2**256) - 1);
    }
    
    function startStakingPhase() public onlyOwner {
        // require(stakingPhaseStop,"Charity: Staking phase not stoped");
        require(!stakingPhase,"Charity: Staking Phase already started");
        stakingPhase = true;
    }
    
    function addProject(address _projectOwner) external onlyOwner {
        for(uint i =0; i < projects.length; i++){
            require(_projectOwner != projects[i], "Charity: the address already added to the list");
        }
        projects.push(_projectOwner);
        // depositAllow[_projectOwner] = true;
    }
    
    function stake(uint256 _projectId, uint256 _amount) external {
        require(_projectId < projects.length,"Charity: project id does not exists");
        // require(depositAllow[projects[_projectId]],"Charity: Deposit not allowed");
        stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        masterchef.deposit(pid,_amount, address(0));
        depositAmount[projects[_projectId]] = depositAmount[projects[_projectId]].add(_amount);
        userAmount[address(msg.sender)][charityRound] = userAmount[address(msg.sender)][charityRound].add(_amount);
        require(userAmount[address(msg.sender)][charityRound] <= maxDeposit,"Charity: User deposit limit exceeded");
        totalAmount[charityRound] = totalAmount[charityRound].add(_amount);
        totalRewards[charityRound] = IBEP20(rewardToken).balanceOf(address(this));
    }
    
    function stopStakingPhase() public onlyOwner {
        // require(!stakingPhaseStop,"Charity: Staking phase already stopped");
        require(stakingPhase,"Charity: Staking phase not started");
        stakingPhase = false;
        masterchef.withdraw(pid,totalAmount[charityRound]);
        reset();
    }
    
    function claim(uint256 _charityRound) public {
        require(_charityRound < charityRound,"Charity: Charity round not ready for claim");
        // uint256 reward = userAmount[address(msg.sender)][_charityRound] + ((totalRewards[_charityRound] * (userAmount[address(msg.sender)][_charityRound])) / (totalRewards[_charityRound]) );
        uint256 reward = ( totalRewards[_charityRound] * userAmount[address(msg.sender)][_charityRound] ) / totalAmount[_charityRound] ; 
        if(reward > 0) {
            IBEP20(rewardToken).safeTransfer(address(msg.sender), reward);
        }
        return;
    }
    
    function reset() private {
        require(!stakingPhase,"Charity: Staking phase not started");
        totalRewards[charityRound]= IBEP20(rewardToken).balanceOf(address(this));
        charityRound++;
        delete projects;
    }
    
    function viewProjects() public view returns(address[] memory) {
        return projects;
    }
}