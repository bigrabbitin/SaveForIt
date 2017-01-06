pragma solidity ^0.4.6;

/*
Contract that automatically distributes money among wallets.
*/
contract Redistribution {

  address owner;

  struct Benificiary {
    address addr;
    uint8 weight;
    bool hasmax;
    uint256 max;
  }

  mapping (uint => Benificiary) benificiaries;
  uint numBenificiaries;

  function Redistribution() {
    owner = msg.sender;
  }

  // Default function that accepts deposits. Doesn't do much
  function () payable {
    // Accept the deposit.
  }

  // Restrict to only owner
  modifier onlyOwner {
    if (msg.sender != owner) throw;
    _;
  }


  function kill() onlyOwner {
    selfdestruct(owner);
  }

  // Add address
  function addAddress(address _to, uint8 _weight) onlyOwner returns (bool success) {
    benificiaries[numBenificiaries++] = Benificiary(_to, _weight, false, 0);
    return true;
  }

  /// Add the given address to the redistribution
  function addAddressWithMax(address _to, uint8 _weight, uint256 _max) onlyOwner returns (bool success) {
    // TODO: We should withdraw everything before we add an address. Else,
    // it might be unfair.

    // What if the address already exists?

    benificiaries[numBenificiaries++] = Benificiary(_to, _weight, true, _max);
    return true;
  }

  // Deposit all pending money into the benificiaries' accounts
  function withdraw() returns (bool success) {
    address me = address(this);
    uint256 currentBalance = me.balance;

    if (currentBalance <= 0) return true;

    uint256 extraBalance;
    uint totalWeight;
    uint nextTotalWeight;
    uint256 prevBalance;

    // Total up all the weights.
    for (uint i=0; i < numBenificiaries; i++) {
      totalWeight += benificiaries[i].weight;
    }

    (extraBalance, nextTotalWeight) = processDistributions(currentBalance, totalWeight);

    // Re-process distributions till either we have no extraBalance or we can't
    // process any more.
    while (extraBalance > 0 && prevBalance != extraBalance) {
      prevBalance = extraBalance;
      (extraBalance, nextTotalWeight) = processDistributions(prevBalance, nextTotalWeight);
    }

    // TODO what about the dust when the weights are not perfectly divisible?
    return true;
  }

  function processDistributions(uint256 amount, uint totalWeight) internal returns (uint256 eb, uint newTW) {
    newTW = totalWeight;

    for (uint j=0; j < numBenificiaries; j++) {
      uint256 amt1 = amount / totalWeight * benificiaries[j].weight;
      // If balance is already over max, just skip this guy
      if (benificiaries[j].hasmax && benificiaries[j].addr.balance >= benificiaries[j].max) {
        eb += amt1;
        newTW -= benificiaries[j].weight;
        continue;
      }
      // If the amount will put them over, reduce the amount so that they end up with only the max.
      if (benificiaries[j].hasmax && (benificiaries[j].addr.balance + amt1) > benificiaries[j].max) {
        uint256 extra = benificiaries[j].addr.balance + amt1 - benificiaries[j].max;
        amt1 -= extra;
        eb += extra;
        newTW -= benificiaries[j].weight;
      }

      // Then send the amount. The extra balance will be sent in the second pass.
      if (! benificiaries[j].addr.send(amt1)) {
        // Couldn't send. Now what?
      }
    }

    return (eb, newTW);
  }

}
