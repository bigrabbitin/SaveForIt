pragma solidity ^0.4.6;

/*
Main contract for SaveForIt, a DApp that helps you save up for stuff and other life goals
*/

contract SaveForIt {
  address public owner;
  address public parent;

  // Factory that creates these contracts.
  SaveForItFactory factory;

  // Constructor. Save all needed info.
  function SaveForIt(address _owner, address _parent, SaveForItFactory _factory) {
    owner = _owner;
    parent = _parent;
    factory = _factory;
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
    // TODO: This seems to be running out of gas when called from another contract, but fine when called
    // from a user.
    unprocessedFunds += msg.value;
  }

  // Function that adds a predistribution account. A predistribution account gets funds
  // before this contract itself gets them.
  // Note, _percentShare is 0 <= _percentShare <= 100
  // TODO: How to remove a account?
  function updatePredistributionAccount(address _to, uint8 _percentShare) onlyOwner returns (bool success) {
    if (_percentShare > 100) throw; // Can't allocate more than 100%

    // Ensure that the address _to was created by this contract. What we really want to check is that
    // address _to is a instance of this contract, but there doesn't seem to be any easy way to do that.
    if (reversePredis[_to] == 0) {
      // Account is not created here. Freak out.
      throw;
    } else {
      // Before updating, check to make sure that the new percentShare total won't be over 100
      if (! ensurePercentTotal(-predis[reversePredis[_to]].percentShare +_percentShare )) throw;

      predis[reversePredis[_to]].percentShare = _percentShare;
    }

    // TODO: When we throw(), do the modifications made to the contract variable before
    // the throw() stick? Or are they roleld back?
    return true;
  }

  // Add a new Predistribution account. A new contract will be created and its address is returned.
  function addPredistributionAccount(uint8 _percentShare) onlyOwner returns (address newAccount) {
    if (_percentShare > 100) throw; // Can't allocate more than 100%
    // Before adding, check to make sure that the new percentShare total won't be over 100
    if (! ensurePercentTotal(_percentShare )) throw;

    // Create a new contract address
    newAccount = factory.create(owner, this);

    // Then Add the contract to the maps.
    predis[nextSerialNumber] = PredisChildren(newAccount, _percentShare);
    reversePredis[newAccount] = nextSerialNumber;
    nextSerialNumber++;

    return newAccount;
  }

  // Set the max amount of wei this account will take. If over, then send it to the next overflow account.
  // TODO: Allow multiple overflow accounts, with percentages just like the predistribution.
  function setAccountMax(uint256 _max, address _overflow_to) onlyOwner returns (bool success) {
    max = _max;
    overflow_to = _overflow_to;
  }

  // Ensure that the existing predistribution percentage totals + additionalValue is not over 100.
  // Note that this function returns true/false, the caller has to determine whether to throw;
  function ensurePercentTotal(uint8 additionalValue) internal returns (bool success) {
    uint8 totalPercentage;

    // Ensure that predis total < 100
    for(uint8 i = 1; i < nextSerialNumber; i++) {
      totalPercentage += predis[i].percentShare;
      if (totalPercentage > 100) return false;
    }

    if (totalPercentage + additionalValue > 100) return false;

    return true;
  }

  // Process all unprocessedFunds.
  function process() returns (bool success) {
    if (unprocessedFunds == 0) return true;

    uint256 accountBalance = address(this).balance - unprocessedFunds;

    // First pass, ensure that predis total < 100
    if (! ensurePercentTotal(0)) throw;
    // It is fine if totalPercentage < 100, it just means the remaining amount becomes part of this account.

    // Send money to all the predistribution children.
    // TODO: Should we process predistributions even if this account has reached max? Right now the answer is yes.
    uint256 moneySent;
    for(uint8 i = 1; i < nextSerialNumber; i++) {
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

    // Go and process the contract for everyone.
    for(i = 1; i < nextSerialNumber; i++) {
      if (predis[i].percentShare == 0) continue;  // Nothing to do for this address

      SaveForIt(predis[i].addr).process();
    }
  }

}

// Factory for creating SaveForIt contracts
contract SaveForItFactory {
  address public firstContract;

  // First time users, do this.
  function deploy() {
    address owner = msg.sender;
    firstContract = create(owner, owner);
  }

  function create(address owner, address parent) returns (address child) {
    child = new SaveForIt(owner, parent, this);

    return child;
  }
}
