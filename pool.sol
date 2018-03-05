pragma solidity ^0.4.18;

/*

Pool Buyer

*/

// ERC20 Interface: https://github.com/ethereum/EIPs/issues/20
contract ERC20 {
  function transfer(address _to, uint256 _value) public returns (bool success);
  function balanceOf(address _owner) public constant returns (uint256 balance);
}

// Interface to ICO Contract
contract Contribution {
  uint256 public maxGasPrice;
  uint256 public startBlock;
  uint256 public totalNormalCollected;
  uint256 public finalizedBlock;
  function proxyPayment(address _th) public payable returns (bool);
}

contract Buyer {
  // Store the amount of ETH deposited by each account.
  mapping (address => uint256) public deposits;

  // Track whether the contract has bought tokens yet.
  bool public bought_tokens;

  // configurable
  bool take_fee = false;
  uint MAX_INDIVIDUAL_CAP = 50 ether;
  uint256 limit = 500; //eth
  uint PERCENT_FEE_RATIO = 10; // 0.1%
  address SALE_CONTRACT_ADDRESS = 0x55d34b686aa8C04921397c5807DB9ECEdba00a4c;
  address TOKEN_CONTRACT_ADDRESS = 0x744d70FDBE2Ba4CF95131626614a1763DF805B9E;
  address pool_owner_address = 0x0;

  Contribution public sale = Contribution(SALE_CONTRACT_ADDRESS);
  ERC20 public token = ERC20(TOKEN_CONTRACT_ADDRESS);  
  
  function getPoolFee(uint256 summ) public view returns (uint256 fee) {
    // calculate pool fee    
    fee = 0;

    if (take_fee) {      
      fee = summ / 100 / PERCENT_FEE_RATIO;
    }
       
    return fee;
  }
  
  function withdraw() internal {
    // Withdraws all ETH/tokens owned by the user in the ratio currently 
    // owned by the contract.

    // Store the user's deposit prior to withdrawal in a temporary variable.
    uint256 userDeposit = deposits[msg.sender];

    // Update the user's deposit prior to sending ETH to prevent recursive call.
    deposits[msg.sender] = 0;

    // Retrieve current ETH balance of contract .
    uint256 contractEthBalance = this.balance;

    // Retrieve current token balance of contract.
    uint256 contractTokenBalance = token.balanceOf(address(this));
    // Calculate total SNT value of ETH and SNT owned by the contract.
    // 1 ETH Wei -> 10000 SNT Wei
    uint256 contract_value = (contractEthBalance * 10000) + contractTokenBalance;

    // Calculate amount of ETH to withdraw.
    uint256 ethAmount = (userDeposit * contractEthBalance * 10000) / contract_value;

    // Calculate amount of tokens to withdraw.
    uint256 tokenAmount = 10000 * ((userDeposit * contractTokenBalance) / contract_value);
    
    uint256 fee = getPoolFee(tokenAmount);
    
    // Send the funds.  Throws on failure to prevent loss of funds.
    if (!token.transfer(msg.sender, tokenAmount - fee)) 
      revert();
    
    //if (bool(pool_owner_address) && bool(fee)) {
    //  if (!token.transfer(pool_owner_address, fee)) 
    //    throw;
    //}

    msg.sender.transfer(ethAmount);
  }
     
  // Buys tokens in the crowdsale and rewards the sender.  Callable by anyone.
  function buy() public {
    // Short circuit to save gas if the contract has already bought tokens.
    if (bought_tokens) 
      return;
    // Record that the contract has bought tokens first to prevent recursive call.
    bought_tokens = true;
    // Transfer all the funds to the ICO contract 
    // to buy tokens.  Throws if the crowdsale hasn't started yet or has 
    // already completed, preventing loss of funds.
    sale.proxyPayment.value(this.balance)(address(this));    
  }
    
  function process_user_txn() internal {    
    // Only allow deposits if the contract hasn't already purchased the tokens.
    if (!bought_tokens) {
      // Update records of deposited ETH to include the received amount.
      deposits[msg.sender] += msg.value;
      // Block each user from contributing more than max individual cap
      if (deposits[msg.sender] > MAX_INDIVIDUAL_CAP) 
        revert();
    } else {
      // Reject ETH sent after the contract has already purchased tokens.
      if (msg.value != 0) 
        revert();
      
      // Withdraw user's funds if they sent 0 ETH to the contract 
      // after the ICO.
      withdraw();      
    }
  }
  
  // Default function.  Called when a user sends ETH to the contract.
  function () payable public {
    // Avoid recursively buying tokens when the sale contract refunds ETH.
    if (msg.sender == address(sale)) 
      return;
    
    process_user_txn();
  }
}