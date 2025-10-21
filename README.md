# Ganit - Maths Dual Battle

Ganit is a multiplayer maths dual battle game where two players compete against each other in a minute long maths quiz and the one who solves more questions wins the battle. The Game is built usin the Arcology Network's Parallel Apis and Container Data Structures allowing true concurrency and parallelization, thus enabling scalability of the project.
## Concurrent Data Structures Used
### 1. AddressU256CumMap - Concurrent Player Statistics

```
AddressU256CumMap public playerScores = new AddressU256CumMap();
AddressU256CumMap public playerGamesPlayed = new AddressU256CumMap();
AddressU256CumMap public playerWins = new AddressU256CumMap();
```
Purpose: These allow multiple players to update their statistics simultaneously without conflicts.

Concurrency Benefit:

- Player A can update their score while Player B updates theirs in parallel
- No locks needed - the cumulative nature handles concurrent additions automatically
- Example: 1000 players can finish games and update win counts simultaneously

### 2. U256Cum - Global Game Counters

```
U256Cum public totalGames = new U256Cum(0, type(uint256).max);
U256Cum public activeGames = new U256Cum(0, type(uint256).max);
U256Cum public completedGames = new U256Cum(0, type(uint256).max);
```
Purpose: Track global statistics that multiple transactions modify concurrently.

Concurrency Benefit:

- Multiple games can be created simultaneously (totalGames.add(1))
- Games can end while new ones start (activeGames.sub(1) + activeGames.add(1))
- No race conditions when updating counters

### 3. U256 Array - Game Results
```
U256 public gameResults = new U256();
```
Purpose: Store game results in a thread-safe array that supports parallel writes.

### Deferred Execution for Parallel Processing
```
constructor() {
    Runtime.defer("createGame(address)", 30000);
    Runtime.defer("submitAnswer(uint256,uint256,uint256)", 25000);
}
```
What This Does:

createGame calls are batched and executed in parallel (up to 30,000 at once)
submitAnswer calls are batched and executed in parallel (up to 25,000 at once)
Arcology processes these batches using parallel execution

## Concurrency in Action - Key Scenarios
### Scenario 1: Parallel Game Creation
```
function createGame(address player2) external returns (uint256 gameId) {
    // Multiple players can create games simultaneously
    totalGames.add(1);        // Concurrent counter increment
    activeGames.add(1);       // Concurrent counter increment
    
    // Each player's stats updated concurrently
    playerGamesPlayed.set(msg.sender, int256(1), 0, type(uint256).max);
    playerGamesPlayed.set(player2, int256(1), 0, type(uint256).max);
}
```
Parallel Execution:

- 1000 different player pairs can create games simultaneously
- All totalGames.add(1) operations execute in parallel
- No waiting for other transactions to complete

### Scenario 2: Concurrent Answer Submission

```
function submitAnswer(uint256 gameId, uint256 questionId, uint256 answer) external {
    if (isCorrect) {
        // Multiple players can update scores simultaneously
        playerScores.set(msg.sender, int256(CORRECT_ANSWER_POINTS), 0, type(uint256).max);
    }
}
```

### Scenario 3: Parallel Game Endings
```
function _endGame(uint256 gameId) internal {
    activeGames.sub(1);      // Concurrent decrement
    completedGames.add(1);   // Concurrent increment
    
    if (winner != address(0)) {
        playerWins.set(winner, int256(1), 0, type(uint256).max); // Concurrent win tracking
    }
    
    gameResults.push(uint256(uint160(winner))); // Concurrent array append
}
```
Parallel Execution:

- Multiple games can end simultaneously
- Global counters updated without conflicts
- Winner statistics updated in parallel

## Why This Matters for Gaming
### Without Concurrency (Traditional Blockchain):
```
Game 1 creates → waits for completion → Game 2 creates → waits → Game 3 creates...
Player A answers → waits → Player B answers → waits → Player C answers...
```

### With Arcology Concurrency
```
Games 1-1000 create simultaneously ⚡
Players A, B, C, D... all answer at the same time ⚡
Multiple games end and update stats in parallel ⚡
```

### Performance Impact
Traditional Approach:

- 1000 game creations = 1000 sequential transactions
- Time: ~1000 block times    

Concurrent Approach:

- 1000 game creations = 1 batch execution
- Time: ~1 block time

### Data Race Prevention
The concurrent data structures handle common race conditions automatically:
```
// Safe: Multiple transactions can do this simultaneously
playerScores.set(playerA, int256(10), 0, type(uint256).max); // +10 points
playerScores.set(playerB, int256(15), 0, type(uint256).max); // +15 points
playerScores.set(playerA, int256(5), 0, type(uint256).max);  // +5 more points

// Result: PlayerA = 15, PlayerB = 15 (no lost updates)
```
This design enables massively multiplayer gaming where thousands of players can interact simultaneously without the typical blockchain bottlenecks!