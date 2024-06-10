### [S-#] Title (ROOT CAUSE + IMPACT)

**Description:** 

**Impact:** 

**Proof of Concept:**

**Recommended Mitigation:** 


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