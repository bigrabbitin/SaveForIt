pragma solidity ^0.4.6;

/*
Main contract for SaveForIt, a DApp that helps you save up for stuff and other life goals
*/

contract SaveForIt {
  address owner;

  // Constructor. Save all needed info.
  function SaveForIt() {
    owner = msg.sender;
    // TODO: Maybe even store the parent contract?
  }

  // Struct that holds all the sub-accounts that this contract will distribute
  // all new incoming transactions to
  struct PredisChildren {
    address addr;
    uint8 percentShare;
  }

  // Because solidity doesn't allow us to iterate over a map to identify all keys,
  // we maintain two maps to be able to look up all addresses
  mapping (uint8 => PredisChildren) predis;   // serial num -> struct. NOTE: starts indexing at 1
  mapping (address => uint8) reversePredis;   // address -> serial number

  // Because the reversePredis uses 0 as a "not found", we need to start indexing at 1
  uint8 nextSerialNumber = 1;

  // Money that has come in, but not been distributed yet.
  uint256 public unprocessedFunds;

  // Max amount of wei this account can have. Any further funds are sent off to the overflow account.
  uint256 public max;
  // Chained account that recieves overflow funds.
  address overflow_to;


  // Restrict to only owner
  modifier onlyOwner {
    if (msg.sender != owner) throw;
    _;
  }

  // Contract can be killed, returning all funds back to the original owner.
  function kill() onlyOwner {
    selfdestruct(owner);
  }


  // The default fallback function that is invoked when sending either. This function
  // won't have a lot of gas, so basically just record that we got some funds that need
  // to be processed.
  function() payable {
    unprocessedFunds += msg.value;
  }

  // Function that adds a predistribution account. A predistribution account gets funds
  // before this contract itself gets them.
  // Note, _percentShare is 0 <= _percentShare <= 100
  // TODO: How to remove a account?
  function addPredistributionAccount(address _to, uint8 _percentShare) onlyOwner returns (bool success) {
    if (_percentShare > 100) throw; // Can't allocate more than 100%

    // First, see if we already have a record of the account. If we do, all we need
    // to do is update the percentShare.
    if (reversePredis[_to] > 0) {
      // Existing account, just update the percentage
      predis[reversePredis[_to]].percentShare = _percentShare;
    } else {
      // Create new account
      // TODO: Actually create the contract here instead of accepting an address. This way, we can be sure that
      // there are no circular references.
      predis[nextSerialNumber] = PredisChildren(_to, _percentShare);
      reversePredis[_to] = nextSerialNumber;
      nextSerialNumber++;
    }

    // TODO: ensure that percentShare total is < 100 for all the accounts.
    // TODO: When we throw(), do the modifications made to the contract variable before
    // the throw() stick? Or are they roleld back?

    return true;
  }

  // Set the max amount of wei this account will take. If over, then send it to the next overflow account.
  // TODO: Allow multiple overflow accounts, with percentages just like the predistribution.
  function setAccountMax(uint256 _max, address _overflow_to) onlyOwner returns (bool success) {
    max = _max;
    overflow_to = _overflow_to;
  }

  // Process all unprocessedFunds.
  function process() returns (bool success) {
    if (unprocessedFunds == 0) return true;

    uint8 totalPercentage;
    uint256 accountBalance = address(this).balance - unprocessedFunds;

    // First pass, ensure that predis total < 100
    for(uint8 i = 1; i < nextSerialNumber; i++) {
      if (predis[i].percentShare == 0) continue;  // Nothing to do for this address

      totalPercentage += predis[i].percentShare;
      if (totalPercentage > 100) throw;
    }
    // It is fine if totalPercentage < 100, it just means the remaining amount becomes part of this account.

    // Send money to all the predistribution children.
    // TODO: Should we process predistributions even if this account has reached max? Right now the answer is yes.
    uint256 moneySent;
    for(i = 1; i < nextSerialNumber; i++) {
      if (predis[i].percentShare == 0) continue;  // Nothing to do for this address

      // Send the percentage of share to the predistribution address.
      uint256 moneyToSend = unprocessedFunds * predis[i].percentShare / 100;
      if (predis[i].addr.send(moneyToSend)) {
        moneySent += moneyToSend;
      }
    }

    uint256 moneyRemaining = unprocessedFunds - moneySent;
    if (moneyRemaining == 0) return true;

    // Check if this account is over max.
    if ( (accountBalance + moneyRemaining) > max) {
      // Send extra money to the overflow account
      if (!overflow_to.send((accountBalance + moneyRemaining) - max)) {
          // TODO: Now what?
      }
    }

    // Everything was processed.
    unprocessedFunds = 0;

    // TODO: trigger processing for all children.
  }

}
