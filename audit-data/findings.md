### [H-1] The `refund` function allows an attacker to re-enter and refund the `entranceFee` multiple times (The address of the player is reset after the fee was sent, posing a Reentrancy threat)

**Description:** 
The protocol states: "Users are allowed to get a refund of their ticket & `value` if they call the `refund` function". The `refund` function is changing state after the refund was sent, meaning that an attacker might re-enter at the point before his address gets changed to the zero address and extract the refund value multiple times.

**Impact:**
The attacker can drain all of the native ETH balance in the contract, when executing the Reentrancy Attack multiple times before his address gets set to the zero address.

**Proof of Concept:**
Take a look at this code snippet:
```solidity
    require(playerAddress != address(0), "PuppyRaffle: Player already refunded, or is not active");

    payable(msg.sender).sendValue(entranceFee);

    players[playerIndex] = address(0);
```

If a malicious actor re-enters the function before the statement `players[playerIndex] = address(0);` is reached, he can execute the `payable(msg.sender).sendValue(entranceFee);` statement multiple times and drain native ETH out of the contract's balance.

**Recommended Mitigation:**
- Reset the players address before refunding the entrance fee


### [H-2] Every user can call the `refund` function and get their paid value back, even when they have won the raffle, resulting in miscalculated collected fees

**Description:**
The protocol states: "Users are allowed to get a refund of their ticket & value if they call the refund function"
It is not exactly clear from the description if this is intended, but the `refund` function can be called by anyone - even the raffle winner. This means that all players of the raffle can refund their entrance fee and get their raffle entries replaced with the zero address. But the collected fee amount is calculated by the `players` array length, which does not change - only the array elements are updated. This means when all players refund their entries (protocol has 0 profits), a winner is still chosen and paid out 80% of the `players.length` * `entranceFee` price pool. For example, if the entrance fee is 100 wei and 5 players are active, the total price pool in the contract is 500 wei. If 3 players refund their tickets now, there are still 5 entries with 3 zero addresses and 2 real addresses in the `player` array, resulting in a payout of 400 wei (80% of 500 wei) to the winner address, while only 200 wei was collected through entrance fees (plus the NFT and money sent will be burned if a zero address is chosen as the winner).

**Impact:**
Every time more than 1 player refunds his ticket, the protocol will make losses with a value of (entrance fee * players) - (entrance fee * refunds) + 80% * (`entranceFee` * `players.length`). So in the above example the loss will be (100 wei * 5 players) - (100 wei * 5 refunds) + 80% of (100 wei * 5 players) = 400 wei. Over the time, the funds of the contract will be drained every time more than 1 player refunds his ticket.

**Proof of Concept:**
refund function (snippet):
```solidity
    ...
    payable(msg.sender).sendValue(entranceFee);

    players[playerIndex] = address(0);
```

selectWinner function (snippet):
```solidity
    uint256 totalAmountCollected = players.length * entranceFee;
    uint256 prizePool = (totalAmountCollected * 80) / 100;
    ...
    (bool success,) = winner.call{value: prizePool}("");
```

**Recommended Mitigation:** 
- Check the `players` array for any zero addresses and only include the active player addresses when calculating the price pool
For example like so:
```solidity
    uint256 activePlayers = 0;
    for (uint256 i = 0; i < players.length; i++) {
            if (players[i] != address(0)) {
                activePlayers += 1;
            }
        }
    uint256 totalAmountCollected = activePlayers * entranceFee;
    ...
```


### [H-3] The `enterRaffle` function does not check if the provided addresses are an EOA or a contract address, resulting in an unfair advantage for some players

**Description:**
The `enterRaffle` function does not verify that the input array of `newPlayers` addresses do not contain any contract or zero addresses. A malicious actor might deploy multiple smart contracts and register them in the raffle, increasing his chance to win the raffle as he can input as much addresses of his own as he wants. This creates an unfair advantage where malicious actors can influence their raffle win probability until the `players` array is completely filled.

**Impact:**
A malicious actor can control the raffle in his favor, so he can increase his win chance drastically.

**Proof of Concept:**
This is the `enterRaffle` function:
```solidity
    require(msg.value == entranceFee * newPlayers.length, "PuppyRaffle: Must send enough to enter raffle");
    for (uint256 i = 0; i < newPlayers.length; i++) {
        players.push(newPlayers[i]);
    }

    // Check for duplicates
    for (uint256 i = 0; i < players.length - 1; i++) {
        for (uint256 j = i + 1; j < players.length; j++) {
            require(players[i] != players[j], "PuppyRaffle: Duplicate player");
        }
    }
    emit RaffleEnter(newPlayers);
```

Any player can input any address and increase their chance of being selected.

**Recommended Mitigation:**
- Let each address only enter 1 address for the raffle
- Make sure that no player address is a contract or zero address
- Make sure that the address is not freshly created and in the best case has some transactional record on the Blockchain


### [H-4] The functionality of the `withdrawFees` function is relying on the contract's balance, posing the risk to make this function un-callable

**Description:** 
The functionality of the `withdrawFees` function is relying on the contract's balance being equal to the total collected fees before being executable, to ensure that no raffle is active at this moment. A potential malicious actor can force ETH into the contract by creating a smart contract and `sellfdestruct`ing it, sending the ETH in the destroyed contract to the PuppyRaffle contract, making the require statement always false.

**Impact:**
The `withdrawFees` function is not callable anymore

**Proof of Concept:**
This is the `withdrawFees` function (snippet):
```solidity
    require(address(this).balance == uint256(totalFees), "PuppyRaffle: There are currently players active!");
    
    ...
```

If a malicious attacker forces ETH into the contract, the require statement will always result in `false`, making it impossible for the owner to withdraw acquired fees.

**Recommended Mitigation:**
- Add the onlyOwner modifier to the function, so no other users can withdraw fees on behalf of the owner
- Check that the raffle is over and no active players are present before withdrawing the fees


### [H-5] The random selection of the raffle winner and NFT rarity is relying on static data and is therefore not random

**Description:**
Relying on blockchain data for randomization is highly discouraged, as attackers can craft a smart contract that calculates the function outcome before sending it. This means that a malicious actor can call the `selectWinner` function only if his own playerIndex will be calculated. The NFT rarity calculation is influenced by the same vulnerability, enabling an attacker to only call the function when his playerIndex is chosen as a winner AND the rarity of the NFT is legendary. This means that the attacker can win each raffle when deploying such a smart contract.

**Impact:** 
Allows an attacker to always win the raffle (NFT + Prize Pool)

**Proof of Concept:**
selectWinner function (snippet):
```solidity
    ...

    uint256 winnerIndex = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % players.length;
    address winner = players[winnerIndex];

    ...

    uint256 rarity = uint256(keccak256(abi.encodePacked(msg.sender, block.difficulty))) % 100;
```


**Recommended Mitigation:**
- Either make the `selectWinner` function internal or onlyOwner, or:
- Deploy an Oracle that provides the contract with better random data


### [M-1] The `enterRaffle` function enables a potential DOS attack vector, if no active players are in the Raffle (No check for `newPlayers`=[], resulting in a potential DOS attack)

**Description:** 
The `enterRaffle` function supports an empty `newPlayers` array as an input parameter. The `players` array keeps track of all active players in the raffle. If there are no active players (`players`=[]) and a malicious actor calls the `enterRaffle` function with an empty `newPlayers` array as input parameter, the statement `i < players.length - 1` results in an Underflow Condition, where the right side of the statement is equal to `uint256.max` and the for loop will run for a long time before running out of gas. This could pose a serious security risk, where an attacker can DOS the protocol by repeatedly calling the `enterRaffle` function with an empty array once no active players are in the raffle to bind processing resources and stop new players from entering the raffle.

**Impact:**
The protocol could experience a Denial of Service due to being busy with processing the for loop. In this way an attacker could also stop new players from entering the raffle, as the contract will be unresponsive while the attacker keeps calling the `enterRaffle` function.

**Proof of Concept:**
Take a look at this function:
```solidity
    for (uint256 i = 0; i < players.length - 1; i++) {
        for (uint256 j = i + 1; j < players.length; j++) {
            require(players[i] != players[j], "PuppyRaffle: Duplicate player");
        }
    }
```

If `players.length` is 0, the statement `players.length - 1` will result in an Integer Underflow, meaning that the loop will run 115792089237316195423570985008687907853269984665640564039457584007913129639935 times.

**Recommended Mitigation:** 
- Check that the `players` array is not empty before checking for duplicates
- If you want to stop users from wasting gas, you can also require that the provided `newPlayers` is also not empty (in case someone might call it with an empty list, as this will have no effect on the `players` array but the user will pay the transactions fees)


### [M-2] When more than one player refunds his entrance fee, no more player can enter the raffle

**Description:**
When calling the `refund` function, the player's raffle entry gets set to the zero address. But the `enterRaffle` function requires no duplicate entries present in the `players` array to let new players enter the raffle. This means if more than one player refunds his entrance fee, more than one zero address will be present in the `players` array, disabling new players to enter the raffle.

**Impact:**
New players are not able to enter the raffle

**Proof of Concept:**
refund function (snippet):
```solidity
    ...

    players[playerIndex] = address(0);
```

enterRaffle function (snippet):
```solidity
    ...

    // Check for duplicates
    for (uint256 i = 0; i < players.length - 1; i++) {
        for (uint256 j = i + 1; j < players.length; j++) {
            require(players[i] != players[j], "PuppyRaffle: Duplicate player");
        }
    }
```

**Recommended Mitigation:** 
- Add a check in the enterRaffle function to exclude zero addresses from the duplicate checking like so:
enterRaffle function (snippet):
```solidity
    ...

    // Check for duplicates
    for (uint256 i = 0; i < players.length - 1; i++) {
        for (uint256 j = i + 1; j < players.length; j++) {
            if(players[i] == address(0) && players[j] == address[0]) {
                continue;
            }
            require(players[i] != players[j], "PuppyRaffle: Duplicate player");
        }
    }
```


### [L-1] The `withdrawFees` function is callable by anyone, making the protocol vulnerable to price manipulation

**Description:** 
The `withdrawFees` function is callable by anyone (external) and only checks that no players are active when withdrawing the fees.

**Impact:** 
The protocol's price could be influenced, if an attacker calls the `withdrawFees` function when a lot of fees have accrued. Moving high amounts of tokens out of a contract signals a bullish signal for users and investors, which are more likely to sell and drive the price even further down.

**Proof of Concept:**
Take a look at the function signature:
```solidity
    function withdrawFees() external {
        ...
    }
```

This function is callable by anyone.

**Recommended Mitigation:** 
- add the `onlyOwner` modifier to the function signature like so:
```solidity
    function withdrawFees() external onlyOwner {
        ...
    }
```

### [G-1] Storage variables that are related to the rarity of the NFT are declared for each rarity, resulting in redundancy and overall bad code maintainability

**Description:** 
The image URI, rarity value and name of the NFT for all rarities are declared multiple times in the same way.

**Impact:** 
Higher deployment costs and overall bad code maintainability and readability

**Proof of Concept:**
Look at the following gas reports to see the difference in deployment costs:

Before
| src/PuppyRaffle.sol:PuppyRaffle contract |                 |        |        |        |         |
|------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                          | Deployment Size |        |        |        |         |
| 3506510                                  | 14458           |        |        |        |         |
| Function Name                            | min             | avg    | median | max    | # calls |
| balanceOf                                | 672             | 672    | 672    | 672    | 1       |
| enterRaffle                              | 22183           | 101518 | 103180 | 143177 | 18      |
| getActivePlayerIndex                     | 800             | 898    | 800    | 1291   | 5       |
| players                                  | 702             | 702    | 702    | 702    | 4       |
| previousWinner                           | 448             | 448    | 448    | 448    | 1       |
| refund                                   | 25956           | 48904  | 60378  | 60378  | 3       |
| selectWinner                             | 25608           | 172842 | 231305 | 231305 | 7       |
| tokenURI                                 | 29647           | 29647  | 29647  | 29647  | 1       |
| withdrawFees                             | 23530           | 42214  | 42214  | 60898  | 2       |

After
| src/PuppyRaffle.sol:PuppyRaffle contract |                 |        |        |        |         |
|------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                          | Deployment Size |        |        |        |         |
| 3451220                                  | 14637           |        |        |        |         |
| Function Name                            | min             | avg    | median | max    | # calls |
| balanceOf                                | 627             | 627    | 627    | 627    | 1       |
| enterRaffle                              | 22183           | 101518 | 103180 | 143177 | 18      |
| getActivePlayerIndex                     | 800             | 898    | 800    | 1291   | 5       |
| players                                  | 702             | 702    | 702    | 702    | 4       |
| previousWinner                           | 383             | 383    | 383    | 383    | 1       |
| refund                                   | 25956           | 48904  | 60378  | 60378  | 3       |
| selectWinner                             | 25630           | 160185 | 213577 | 213577 | 7       |
| tokenURI                                 | 29799           | 29799  | 29799  | 29799  | 1       |
| withdrawFees                             | 23596           | 42280  | 42280  | 60964  | 2       |

The actual gas savings are 55290 wei.

**Recommended Mitigation:**
- Group rarity properties inside of a struct
- Add a mapping that maps tokenIds to the Rarity

### [G-2] Storage variable `raffleDuration` should be immutable

**Description:** 
The storage variable `raffleDuration` is a mutable variable, but is only assigned once in the constructor, and cannot be changed by the code afterwards.

**Impact:** 
Higher deployment costs and lower code readability

**Proof of Concept:**
Look at the following gas reports to see the difference in deployment costs:

Before
| src/PuppyRaffle.sol:PuppyRaffle contract |                 |        |        |        |         |
|------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                          | Deployment Size |        |        |        |         |
| 3506510                                  | 14458           |        |        |        |         |
| Function Name                            | min             | avg    | median | max    | # calls |
| balanceOf                                | 672             | 672    | 672    | 672    | 1       |
| enterRaffle                              | 22183           | 101518 | 103180 | 143177 | 18      |
| getActivePlayerIndex                     | 800             | 898    | 800    | 1291   | 5       |
| players                                  | 702             | 702    | 702    | 702    | 4       |
| previousWinner                           | 448             | 448    | 448    | 448    | 1       |
| refund                                   | 25956           | 48904  | 60378  | 60378  | 3       |
| selectWinner                             | 25608           | 172842 | 231305 | 231305 | 7       |
| tokenURI                                 | 29647           | 29647  | 29647  | 29647  | 1       |
| withdrawFees                             | 23530           | 42214  | 42214  | 60898  | 2       |

After
| src/PuppyRaffle.sol:PuppyRaffle contract |                 |        |        |        |         |
|------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                          | Deployment Size |        |        |        |         |
| 3506498                                  | 14458           |        |        |        |         |
| Function Name                            | min             | avg    | median | max    | # calls |
| balanceOf                                | 672             | 672    | 672    | 672    | 1       |
| enterRaffle                              | 22183           | 101518 | 103180 | 143177 | 18      |
| getActivePlayerIndex                     | 800             | 898    | 800    | 1291   | 5       |
| players                                  | 702             | 702    | 702    | 702    | 4       |
| previousWinner                           | 448             | 448    | 448    | 448    | 1       |
| refund                                   | 25956           | 48904  | 60378  | 60378  | 3       |
| selectWinner                             | 25608           | 172842 | 231305 | 231305 | 7       |
| tokenURI                                 | 29647           | 29647  | 29647  | 29647  | 1       |
| withdrawFees                             | 23530           | 42214  | 42214  | 60898  | 2       |

The actual gas savings are 12 wei.

**Recommended Mitigation:**
- Make the `raffleDuration` storage variable immutable

### [I-1] The `RaffleEnter` Event should be renamed to `RaffleEntered`, to be consistent with Event naming

**Description:** 
There are the `RaffleEnter`, `RaffleRefunded`, and `FeeAddressChanged`events declared in the code. The `RaffleEnter` Event should be renamed to `RaffleEntered`, to be consistent with Event naming.

**Impact:** 
Lower code readability and consistency

**Proof of Concept:**
```solidity
    // Events
    event RaffleEnter(address[] newPlayers);
    event RaffleRefunded(address player);
    event FeeAddressChanged(address newFeeAddress);
```

**Recommended Mitigation:**
- Rename the `RaffleEnter` event to `RaffleEntered`


### [I-2] The `getActivePlayerIndex` function returns `0` for the first address in the `players` array, indicating an inactive player and causing confusion to the users, developers and auditors

**Description:** 
The `getActivePlayerIndex` function indicates an active player index by values greater than `0`. But it returns `0` for the first address in the `players` array, which does indicate that the player is not active when he actually is.

**Impact:** 
The `getActivePlayerIndex` function is an external function, so it does not have any impact on the code. Although, the function may cause confusion amongst developers and introduce errors when implemented in the code and following the description of the function.

**Proof of Concept:**
Take a look at the `getActivePlayerIndex` function:
```solidity
    /// @return the index of the player in the array, if they are not active, it returns 0
    function getActivePlayerIndex(address player) external view returns (uint256) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == player) {
                return i;
            }
        }
        return 0;
    }
```

When the address of the first address in the `players` array is supplied as the input argument, the response is `0`, which indicates an inactive player.

**Recommended Mitigation:** 
- Implement a check to see if the player's address is present in the `players` array before returning it's value