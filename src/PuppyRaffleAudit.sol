// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Base64} from "lib/base64/base64.sol";

/// @title PuppyRaffle
/// @author PuppyLoveDAO
/// @notice This project is to enter a raffle to win a cute dog NFT. The protocol should do the following:
/// 1. Call the `enterRaffle` function with the following parameters:
///    1. `address[] participants`: A list of addresses that enter. You can use this to enter yourself multiple times, or yourself and a group of your friends.
/// 2. Duplicate addresses are not allowed
/// 3. Users are allowed to get a refund of their ticket & `value` if they call the `refund` function
/// 4. Every X seconds, the raffle will be able to draw a winner and be minted a random puppy
/// 5. The owner of the protocol will set a feeAddress to take a cut of the `value`, and the rest of the funds will be sent to the winner of the puppy.
contract PuppyRaffle is ERC721, Ownable {
    using Address for address payable;

    uint256 public immutable entranceFee;

    address[] public players;
    // v: [G-2] raffleDuration should be an immutable variable, as it's only assigned once in the constructor
    // q: is it okay to make the raffleDuration public? Why not?
    uint256 public immutable raffleDuration;
    // q: is it okay to make the startTime public? Why not?
    uint256 public raffleStartTime;
    // q: previousWinner is only assigned but never used in the code - could be feature for players to view?
    address public previousWinner;

    // We do some storage packing to save gas
    // q: is it okay to make the feeAddress public? Why not?
    address public feeAddress;
    // q: is it okay to make the totalFees public? Why not?
    uint64 public totalFees = 0;

    // mappings to keep track of token traits
    // v: [G-1] regroup the rarity properties into a struct with common, rare and legendary rarity to save gas
    mapping(uint256 => uint256) public tokenIdToRarity;
    mapping(uint256 => string) public rarityToUri;
    mapping(uint256 => string) public rarityToName;

    // Stats for the common puppy (pug)
    string private commonImageUri = "ipfs://QmSsYRx3LpDAb1GZQm7zZ1AuHZjfbPkD6J7s9r41xu1mf8";
    uint256 public constant COMMON_RARITY = 70;
    string private constant COMMON = "common";

    // Stats for the rare puppy (st. bernard)
    string private rareImageUri = "ipfs://QmUPjADFGEKmfohdTaNcWhp7VGk26h5jXDA7v3VtTnTLcW";
    uint256 public constant RARE_RARITY = 25;
    string private constant RARE = "rare";

    // Stats for the legendary puppy (shiba inu)
    string private legendaryImageUri = "ipfs://QmYx6GsYAKnNzZ9A6NvEKV9nf1VaDzJrqDR23Y8YSkebLU";
    uint256 public constant LEGENDARY_RARITY = 5;
    string private constant LEGENDARY = "legendary";

    // Events
    // v: [I-1] the event should be named `RaffleEntered` to be consistent with the function naming
    event RaffleEnter(address[] newPlayers);
    event RaffleRefunded(address player);
    event FeeAddressChanged(address newFeeAddress);

    /// @param _entranceFee the cost in wei to enter the raffle
    /// @param _feeAddress the address to send the fees to
    /// @param _raffleDuration the duration in seconds of the raffle
    // i: everything looks good for now, except the redundant assignments (gas optimization, [G-1])
    constructor(uint256 _entranceFee, address _feeAddress, uint256 _raffleDuration) ERC721("Puppy Raffle", "PR") {
        entranceFee = _entranceFee;
        feeAddress = _feeAddress;
        raffleDuration = _raffleDuration;
        raffleStartTime = block.timestamp;

        rarityToUri[COMMON_RARITY] = commonImageUri;
        rarityToUri[RARE_RARITY] = rareImageUri;
        rarityToUri[LEGENDARY_RARITY] = legendaryImageUri;

        rarityToName[COMMON_RARITY] = COMMON;
        rarityToName[RARE_RARITY] = RARE;
        rarityToName[LEGENDARY_RARITY] = LEGENDARY;
    }

    /// @notice this is how players enter the raffle
    /// @notice they have to pay the entrance fee * the number of players
    /// @notice duplicate entrants are not allowed
    /// @param newPlayers the list of players to enter the raffle
    //
    // v: [M-1] if the provided msg.value is 0, and newPlayers=[], the require statement will pass (which it shouldn't).
    //    In this case, the first for loop is skipped and the second for loop will check the players array for duplicates (which shouldn't be present). But no harm is being caused.
    //    If the `players` array had no entries, the transaction will run out of gas due to an Underflow exception at: `for (uint256 i = 0; i < players.length - 1; i++) { ... }`. This could maybe function as a DOS attack?
    //
    // i: the newPlayers array gets added to the players array before it is checked for duplicate entry
    // i: if the require() statement is false, the whole transaction seems to be reverted, so the players array is not modified as initially thought.
    // v: [H-3] A player can enter multiple addresses, as he can deploy contracts that he controls, increasing his chance to win the raffle
    // v: [M-2] The duplicate check does not account for zero addresses. If more than one zero address is in he `players` array, no new players can enter the raffle anymore
    function enterRaffle(address[] memory newPlayers) public payable {
        require(msg.value == entranceFee * newPlayers.length, "PuppyRaffle: Must send enough to enter raffle");
        for (uint256 i = 0; i < newPlayers.length; i++) {
            players.push(newPlayers[i]);
        }

        // Check for duplicates
        // i: seems to really check for duplicates
        // v: [M-1] if players.length is 0, the loop will throw an Underflow exception as it equals to i < -1
        // i: But if the `newPlayers` array is not empty, doing `players.length-1` will be no issue, as addresses are added to the array before checking for duplicates. But the user will be paying to add nothing to the `players` array.
        // i: if players.length is 1, the loop will be skipped as i < 0 is already false in the first run. But that's okay as there is only 1 entry in the array and no duplicates can be present
        for (uint256 i = 0; i < players.length - 1; i++) {
            for (uint256 j = i + 1; j < players.length; j++) {
                require(players[i] != players[j], "PuppyRaffle: Duplicate player");
            }
        }
        emit RaffleEnter(newPlayers);
    }

    /// @param playerIndex the index of the player to refund. You can find it externally by calling `getActivePlayerIndex`
    /// @dev This function will allow there to be blank spots in the array
    // v: [H-1] If the line `payable(msg.sender).sendValue(entranceFee)` is re-entered, an attacker can refund fees multiple times
    // v: [H-2] There is no check to see if the raffle was won by the player. If the player won the raffle, he could refund his entranceFee and still get the prize, resulting in a loss for the protocol
    // v: [H-2] Setting the players index to the zero address may be bad. If this player index gets selected as a winner, the reward will be sent to the zero address and be forever lost
    // v: [M-2] Once 2 players have refunded, there are 2 zero address entries in the `players` array. This means calling `enterRaffle` will be impossible as the require statement `require(players[i] != players[j], "PuppyRaffle: Duplicate player");` will always fail and revert the transaction, stopping new players from entering
    // i: There is no check to see if the provided playerIndex is present in the `players` array. Providing an invalid playerIndex throws an `invalid opcode` exception (index out of range)
    function refund(uint256 playerIndex) public {
        address playerAddress = players[playerIndex];
        require(playerAddress == msg.sender, "PuppyRaffle: Only the player can refund");
        require(playerAddress != address(0), "PuppyRaffle: Player already refunded, or is not active");

        payable(msg.sender).sendValue(entranceFee);

        players[playerIndex] = address(0);
        emit RaffleRefunded(playerAddress);
    }

    /// @notice a way to get the index in the array
    /// @param player the address of a player in the raffle
    /// @return the index of the player in the array, if they are not active, it returns 0
    // v: [I-2] When the playerIndex of the player's address is 0, it returns also 0 - indicating that the player is not active when he actually is.
    //    before calling this function, add a check if the player is active like `require(_isActivePlayer)`
    function getActivePlayerIndex(address player) external view returns (uint256) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == player) {
                return i;
            }
        }
        return 0;
    }

    /// @notice this function will select a winner and mint a puppy
    /// @notice there must be at least 4 players, and the duration has occurred
    /// @notice the previous winner is stored in the previousWinner variable
    /// @dev we use a hash of on-chain data to generate the random numbers
    /// @dev we reset the active players array after the winner is selected
    /// @dev we send 80% of the funds to the winner, the other 20% goes to the feeAddress
    // v: [H-5] there could be a replay attack, where the attacker calls selectWinner when the statement
    //   `uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % players.length` results in his playerIndex, so he is the chosen winner
    // v: [H-5] the same could be done with the statement `uint256(keccak256(abi.encodePacked(msg.sender, block.difficulty))) % 100` to get a legendary rarity
    // q: not entirely sure if this is an issue, but in the protocol description it does only say that the winner will get a puppy NFT. But nothing regarding a price pool could be found.
    function selectWinner() external {
        require(block.timestamp >= raffleStartTime + raffleDuration, "PuppyRaffle: Raffle not over");
        require(players.length >= 4, "PuppyRaffle: Need at least 4 players");
        uint256 winnerIndex =
            uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % players.length;
        address winner = players[winnerIndex];
        // v: [H-2] This is bad practice. When players refund their entranceFee, they are getting it back but their entry in the `players` array is set to the zero address.
        //    [H-2] So the players.length does not change and you are sending more money than you have collected.
        uint256 totalAmountCollected = players.length * entranceFee;
        uint256 prizePool = (totalAmountCollected * 80) / 100;
        uint256 fee = (totalAmountCollected * 20) / 100;
        totalFees = totalFees + uint64(fee);

        uint256 tokenId = totalSupply();

        // We use a different RNG calculate from the winnerIndex to determine rarity
        // v: [H-5] this could also be exploited when calling the statement when its resulting in a legendary rarity
        uint256 rarity = uint256(keccak256(abi.encodePacked(msg.sender, block.difficulty))) % 100;
        if (rarity <= COMMON_RARITY) {
            tokenIdToRarity[tokenId] = COMMON_RARITY;
        } else if (rarity <= COMMON_RARITY + RARE_RARITY) {
            tokenIdToRarity[tokenId] = RARE_RARITY;
        } else {
            tokenIdToRarity[tokenId] = LEGENDARY_RARITY;
        }

        delete players;
        raffleStartTime = block.timestamp;
        previousWinner = winner;
        (bool success,) = winner.call{value: prizePool}("");
        require(success, "PuppyRaffle: Failed to send prize pool to winner");
        _safeMint(winner, tokenId);
    }

    /// @notice this function will withdraw the fees to the feeAddress
    // v: [H-4] using this.balance is not advised, as you can force ETH into the contract by selfdestructing it, resulting that the owner can never call this function again
    // v: [L-1] everybody can call this function, which could lead to unexpected behavior - try to add the onlyOwner modifier
    // v: [L-1] When the attacker calls this function and a lot of fees have acquired, may there be any significant impact to the protocol?
    function withdrawFees() external {
        require(address(this).balance == uint256(totalFees), "PuppyRaffle: There are currently players active!");
        uint256 feesToWithdraw = totalFees;
        totalFees = 0;
        (bool success,) = feeAddress.call{value: feesToWithdraw}("");
        require(success, "PuppyRaffle: Failed to withdraw fees");
    }

    /// @notice only the owner of the contract can change the feeAddress
    /// @param newFeeAddress the new address to send fees to
    function changeFeeAddress(address newFeeAddress) external onlyOwner {
        feeAddress = newFeeAddress;
        emit FeeAddressChanged(newFeeAddress);
    }

    /// @notice this function will return true if the msg.sender is an active player
    function _isActivePlayer() internal view returns (bool) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == msg.sender) {
                return true;
            }
        }
        return false;
    }

    /// @notice this could be a constant variable
    function _baseURI() internal pure returns (string memory) {
        return "data:application/json;base64,";
    }

    /// @notice this function will return the URI for the token
    /// @param tokenId the Id of the NFT
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "PuppyRaffle: URI query for nonexistent token");

        uint256 rarity = tokenIdToRarity[tokenId];
        string memory imageURI = rarityToUri[rarity];
        string memory rareName = rarityToName[rarity];

        return string(
            abi.encodePacked(
                _baseURI(),
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"',
                            name(),
                            '", "description":"An adorable puppy!", ',
                            '"attributes": [{"trait_type": "rarity", "value": ',
                            rareName,
                            '}], "image":"',
                            imageURI,
                            '"}'
                        )
                    )
                )
            )
        );
    }
}
