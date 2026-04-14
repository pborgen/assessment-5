// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract HomeTransaction {
    // Constants
    uint constant timeBetweenDepositAndFinalization = 5 minutes;
    uint constant depositPercentage = 10;

    enum ContractState {
        WaitingSellerSignature,
        WaitingBuyerSignature,
        WaitingRealtorReview,
        WaitingFinalization,
        Finalized,
        Rejected }
    ContractState public contractState = ContractState.WaitingSellerSignature;


    // Roles acting on contract
    address payable public realtor;
    address payable public seller;
    address payable public buyer;

    // Contract details
    string public homeAddress;
    string public zip;
    string public city;
    uint public realtorFee;
    uint public price;

    // Set when buyer signs and pays deposit
    uint public deposit;
    uint public finalizeDeadline;

    // Set when realtor reviews closing conditions
    enum ClosingConditionsReview { Pending, Accepted, Rejected }
    ClosingConditionsReview closingConditionsReview = ClosingConditionsReview.Pending;

    constructor(
        string memory _address,
        string memory _zip,
        string memory _city,
        uint _realtorFee,
        uint _price,
        address payable _realtor,
        address payable _seller,
        address payable _buyer) {
        require(_price >= _realtorFee, "Price needs to be more than realtor fee!");

        realtor = _realtor;
        seller = _seller;
        buyer = _buyer;
        homeAddress = _address;
        zip = _zip;
        city = _city;
        price = _price;
        realtorFee = _realtorFee;
    }

    function sellerSignContract() public payable {
        require(seller == msg.sender, "Only seller can sign contract");

        require(contractState == ContractState.WaitingSellerSignature, "Wrong contract state");

        contractState = ContractState.WaitingBuyerSignature;
    }

    function buyerSignContractAndPayDeposit() public payable {
        require(buyer == msg.sender, "Only buyer can sign contract");

        require(contractState == ContractState.WaitingBuyerSignature, "Wrong contract state");

        require(msg.value >= price*depositPercentage/100 && msg.value <= price, "Buyer needs to deposit between 10% and 100% to sign contract");

        contractState = ContractState.WaitingRealtorReview;

        deposit = msg.value;
        finalizeDeadline = block.timestamp + timeBetweenDepositAndFinalization;
    }

    function realtorReviewedClosingConditions(bool accepted) public {
        require(realtor == msg.sender, "Only realtor can review closing conditions");

        require(contractState == ContractState.WaitingRealtorReview, "Wrong contract state");

        if (accepted) {
            closingConditionsReview = ClosingConditionsReview.Accepted;
            contractState = ContractState.WaitingFinalization;
        } else {
            closingConditionsReview = ClosingConditionsReview.Rejected;
            contractState = ContractState.Rejected;

            _send(buyer, deposit);
        }
    }

    function buyerFinalizeTransaction() public payable {
        require(buyer == msg.sender, "Only buyer can finalize transaction");

        require(contractState == ContractState.WaitingFinalization, "Wrong contract state");

        require(msg.value + deposit == price, "Buyer needs to pay the rest of the cost to finalize transaction");

        contractState = ContractState.Finalized;

        _send(seller, price - realtorFee);
        _send(realtor, realtorFee);
    }

    // Cancels the deal during WaitingFinalization, forfeiting the deposit:
    // the realtor is paid (capped at the deposit so the math can't underflow)
    // and any remainder goes to the seller. The buyer may trigger this
    // voluntarily; after the deadline anyone may trigger it on their behalf.
    function cancelAndForfeitDeposit() public {
        require(
            buyer == msg.sender || finalizeDeadline <= block.timestamp,
            "Only buyer can cancel before transaction deadline"
        );

        require(contractState == ContractState.WaitingFinalization, "Wrong contract state");

        contractState = ContractState.Rejected;

        uint feeToRealtor = realtorFee <= deposit ? realtorFee : deposit;
        uint toSeller = deposit - feeToRealtor;

        if (feeToRealtor > 0) _send(realtor, feeToRealtor);
        if (toSeller > 0) _send(seller, toSeller);
    }

    function _send(address payable to, uint amount) private {
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "ETH transfer failed");
    }
}