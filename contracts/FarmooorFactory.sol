// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBlast {
    function configureAutomaticYield() external;
}

contract FarmooorFactory {
    event ContractDeployed(address indexed deployer, address indexed contractAddress);

    // Mapping to keep track of the users and the addresses of their deployed contracts
    mapping(address => address[]) public allUserContracts;
    address[] public allUsers;

    constructor() {}

    function deployContract() external {
        // Deploy the contract
        Farmooor newContract = new Farmooor(msg.sender);
        address newContractAddress = address(newContract);

        // If the user is not already in the list of all users, add them
        if (!userExists(msg.sender)) {
            allUsers.push(msg.sender);
        }

        // Map the user to the deployed contract address
        allUserContracts[msg.sender].push(newContractAddress);

        // Emit event
        emit ContractDeployed(msg.sender, newContractAddress);
    }

    // Function to check if a user exists in the list of all users
    function userExists(address user) internal view returns (bool) {
        return allUserContracts[user].length > 0;
    }

    // Read function to get all addresses of contracts deployed by a given user
    function getUserContracts(address user) external view returns (address[] memory) {
        return allUserContracts[user];
    }

    // Read function to get all users
    function getAllUsers() external view returns (address[] memory) {
        return allUsers;
    }

    // Read function to get all contracts deployed by all users
    // TODO: return (address[] memory, address[][] memory) instead for (allUsers, allUserContracts)
    function getAllUserContracts() external view returns (address[][] memory) {
        // Initialize the array to store all contracts
        address[][] memory allContracts = new address[][](allUsers.length);
        
        // Iterate through each user and add their contracts to the array
        for (uint i = 0; i < allUsers.length; i++) {
            allContracts[i] = allUserContracts[allUsers[i]];
        }

        return allContracts;
    }
}

contract Farmooor {
    IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002);

    // TODO: Do you need the Claimer struct, claimers mapping, and claimerAddresses?
    // Can you consolidate?
    struct Claimer {
        address payable claimerAddress;
        uint256 claimableAmount;
    }

    address public owner;
    mapping(address => Claimer) public claimers;
    address[] public claimerAddresses;

    constructor(address _owner) {
        owner = _owner;
        BLAST.configureAutomaticYield();
    }

    // Function modifier to ensure only the owner can call the function
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    // Function to check if an address already exists in the claimerAddresses array
    // TODO: Use mapping instead
    function addressExists(address _address) internal view returns (bool) {
        for (uint256 i = 0; i < claimerAddresses.length; i++) {
            if (claimerAddresses[i] == _address) {
                return true;
            }
        }
        return false;
    }

    // Owner functions -----

    // Function for the owner to send Ether to multiple addresses
    function multiSend(address[] calldata _recipients, uint256[] calldata _amounts) external onlyOwner {
        require(_recipients.length == _amounts.length, "Arrays length mismatch");

        // Calculate the total amount of Ether being sent out
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            totalAmount += _amounts[i];
        }

        // Ensure the contract has enough balance to send out
        require(address(this).balance >= totalAmount, "Insufficient contract balance");

        for (uint256 i = 0; i < _recipients.length; i++) {
            require(_recipients[i] != address(0), "Invalid recipient address");
            require(_amounts[i] > 0, "Invalid amount");

            // Transfer Ether to the recipient
            payable(_recipients[i]).transfer(_amounts[i]);
        }
    }


    // Function to register a claimer with a specific claimable amount
    function upsertClaim(address payable _claimer, uint256 _claimableAmount) external onlyOwner {
        // Upsert the claim
        claimers[_claimer] = Claimer({
            claimerAddress: _claimer,
            claimableAmount: _claimableAmount
        });

        // Add the claimer address to the array if it's not already present
        if (!addressExists(_claimer)) {
            claimerAddresses.push(_claimer);
        }
    }

    function withdrawBalance() external onlyOwner {
        // Transfer the entire contract balance to the owner
        payable(owner).transfer(address(this).balance);
    }

    // Function for the owner to transfer any ERC-20 tokens out of the contract
    function transferERC20(address _tokenAddress, address _to, uint256 _amount) external onlyOwner {
        IERC20 token = IERC20(_tokenAddress);

        // Ensure the contract has enough balance of the specified ERC-20 token
        require(token.balanceOf(address(this)) >= _amount, "Insufficient ERC-20 balance");

        // Transfer ERC-20 tokens to the specified address
        token.transfer(_to, _amount);
    }

    // Function for the owner to transfer any ERC-721 tokens out of the contract
    function transferERC721(address _tokenAddress, address _to, uint256 _tokenId) external onlyOwner {
        IERC721 token = IERC721(_tokenAddress);

        // Ensure the contract owns the specified ERC-721 token
        require(token.ownerOf(_tokenId) == address(this), "Not owner of ERC-721 token");

        // Transfer ERC-721 token to the specified address
        token.transferFrom(address(this), _to, _tokenId);
    }

    // Non-Owner functions -----

    // Function for a claimer to withdraw their claimable amount
    // TODO: does this have a re-entrancy attack vulnerability?
    function withdrawClaim() external {
        // Retrieve the claimer's information
        Claimer storage claimer = claimers[msg.sender];

        // Ensure the claimer is registered
        require(claimer.claimerAddress == msg.sender, "Claim not found");

        // Ensure the claimable amount is greater than 0
        require(claimer.claimableAmount > 0, "No claimable amount");

        // Transfer the claimable amount to the claimer
        payable(msg.sender).transfer(claimer.claimableAmount);

        // Update the claimable amount to 0 after withdrawal
        claimer.claimableAmount = 0;
    }

    // Function to get all claims available to claimers
    function getAllClaims() external view returns (address[] memory, uint256[] memory) {
        // Initialize arrays to store claimer addresses and claimable amounts
        uint256[] memory claimableAmounts = new uint256[](claimerAddresses.length);

        // Iterate through claimer addresses array and populate claimableAmounts
        for (uint256 i = 0; i < claimerAddresses.length; i++) {
            claimableAmounts[i] = claimers[claimerAddresses[i]].claimableAmount;
        }

        return (claimerAddresses, claimableAmounts);
    }

    // Function to get the claimable amount for a given address
    function getClaim(address _claimer) external view returns (uint256) {
        return claimers[_claimer].claimableAmount;
    }

    // Function to get the ETH balance of the contract
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getOwner() public view returns (address) {
        return owner;
    }

    receive() external payable {}
}
