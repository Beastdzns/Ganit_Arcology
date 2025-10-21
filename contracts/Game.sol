// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@arcologynetwork/concurrentlib/lib/map/AddressU256Cum.sol";
import "@arcologynetwork/concurrentlib/lib/commutative/U256Cum.sol";
import "@arcologynetwork/concurrentlib/lib/array/U256.sol";
import "@arcologynetwork/concurrentlib/lib/runtime/Runtime.sol";

contract Ganit {
    struct Game {
        address player1;
        address player2;
        uint256 startTime;
        uint256 endTime;
        bool active;
        uint256 currentQuestion;
        uint256 questionCount;
    }

    struct Player {
        uint256 score;
        uint256 correctAnswers;
        uint256 wrongAnswers;
        uint256 lastAnswerTime;
    }

    // Parallel Safe DS
    AddressU256CumMap public playerScores = new AddressU256CumMap();
    AddressU256CumMap public playerGamesPlayed = new AddressU256CumMap();
    AddressU256CumMap public playerWins = new AddressU256CumMap();

    U256Cumulative public totalGames = new U256Cumulative(0, type(uint256).max);
    U256Cumulative public activeGames = new U256Cumulative(0, type(uint256).max);
    U256Cumulative public completedGames = new U256Cumulative(0, type(uint256).max);

    U256 public gameResults = new U256();

    mapping(uint256 => Game) public games;
    mapping(uint256 => mapping(address => Player)) public gamePlayers;
    mapping(uint256 => mapping(uint256 => uint256)) public gameQuestions;
    mapping(uint256 => mapping(uint256 => uint256)) public gameAnswers;

    uint256 public constant GAME_DURATION = 60;
    uint256 public constant QUESTIONS_PER_GAME = 20;
    uint256 public constant CORRECT_ANSWER_POINTS = 10;
    uint256 public constant WRONG_ANSWER_PENALTY = 2;

    event GameCreated(uint256 gameId, address player1, address player2);
    event QuestionGenerated(uint256 gameId, uint256 questionId, uint256 num1, uint256 num2, uint256 operation);
    event AnswerSubmitted(uint256 gameId, address player, uint256 questionId, uint256 answer, bool correct);
    event GameEnded(uint256 gameId, address winner, uint256 player1Score, uint256 player2Score);
    event GameStats(uint256 totalGames, uint256 activeGames, uint256 completedGames);

    constructor() {
        // Enable deferred execution for parallel game creation
        Runtime.defer("createGame(address)", 30000);
        Runtime.defer("submitAnswer(uint256,uint256,uint256)", 25000);
    }
    
    function createGame(address player2) external returns (uint256 gameId) {
        require(msg.sender != player2, "Cannot play against yourself");
        
        gameId = uint256(keccak256(abi.encodePacked(
            block.timestamp, 
            msg.sender, 
            player2, 
            totalGames.get()
        )));
        
        games[gameId] = Game({
            player1: msg.sender,
            player2: player2,
            startTime: block.timestamp,
            endTime: block.timestamp + GAME_DURATION,
            active: true,
            currentQuestion: 0,
            questionCount: QUESTIONS_PER_GAME
        });
        
        // Initialize players
        gamePlayers[gameId][msg.sender] = Player(0, 0, 0, 0);
        gamePlayers[gameId][player2] = Player(0, 0, 0, 0);
        
        // Generate questions for the game
        _generateQuestions(gameId);
        
        totalGames.add(1);
        activeGames.add(1);
        
        playerGamesPlayed.set(msg.sender, int256(1), 0, type(uint256).max);
        playerGamesPlayed.set(player2, int256(1), 0, type(uint256).max);
        
        emit GameCreated(gameId, msg.sender, player2);
        return gameId;
    }
    
    function submitAnswer(uint256 gameId, uint256 questionId, uint256 answer) external {
        Game storage game = games[gameId];
        require(game.active, "Game not active");
        require(block.timestamp <= game.endTime, "Game ended");
        require(msg.sender == game.player1 || msg.sender == game.player2, "Not a player");
        require(questionId < QUESTIONS_PER_GAME, "Invalid question");
        
        Player storage player = gamePlayers[gameId][msg.sender];
        require(player.lastAnswerTime < block.timestamp, "Too fast");
        
        uint256 correctAnswer = gameAnswers[gameId][questionId];
        bool isCorrect = (answer == correctAnswer);
        
        if (isCorrect) {
            player.score += CORRECT_ANSWER_POINTS;
            player.correctAnswers++;
            playerScores.set(msg.sender, int256(CORRECT_ANSWER_POINTS), 0, type(uint256).max);
        } else {
            if (player.score >= WRONG_ANSWER_PENALTY) {
                player.score -= WRONG_ANSWER_PENALTY;
            }
            player.wrongAnswers++;
        }
        
        player.lastAnswerTime = block.timestamp;
        
        emit AnswerSubmitted(gameId, msg.sender, questionId, answer, isCorrect);
        
        // Check if game should end
        if (block.timestamp >= game.endTime) {
            _endGame(gameId);
        }
    }
    
    function _generateQuestions(uint256 gameId) internal {
        for (uint256 i = 0; i < QUESTIONS_PER_GAME; i++) {
            uint256 seed = uint256(keccak256(abi.encodePacked(gameId, i, block.timestamp)));
            uint256 num1 = (seed % 50) + 1; // 1-50
            uint256 num2 = ((seed >> 8) % 30) + 1; // 1-30
            uint256 operation = (seed >> 16) % 3; // 0=add, 1=sub, 2=mul
            
            uint256 correctAnswer;
            if (operation == 0) { // Addition
                correctAnswer = num1 + num2;
            } else if (operation == 1) { // Subtraction
                if (num1 < num2) {
                    uint256 temp = num1;
                    num1 = num2;
                    num2 = temp;
                }
                correctAnswer = num1 - num2;
            } else { // Multiplication
                num1 = (num1 % 12) + 1; // Keep smaller for multiplication
                num2 = (num2 % 12) + 1;
                correctAnswer = num1 * num2;
            }
            
            gameQuestions[gameId][i] = (num1 << 128) | (num2 << 64) | operation;
            gameAnswers[gameId][i] = correctAnswer;
            
            emit QuestionGenerated(gameId, i, num1, num2, operation);
        }
    }
    
    function _endGame(uint256 gameId) internal {
        Game storage game = games[gameId];
        require(game.active, "Game already ended");
        
        game.active = false;
        activeGames.sub(1);
        completedGames.add(1);
        
        Player storage player1 = gamePlayers[gameId][game.player1];
        Player storage player2 = gamePlayers[gameId][game.player2];
        
        address winner = player1.score > player2.score ? game.player1 : 
                        (player2.score > player1.score ? game.player2 : address(0));
        
        if (winner != address(0)) {
            playerWins.set(winner, int256(1), 0, type(uint256).max);
        }
        
        gameResults.push(uint256(uint160(winner)));
        
        emit GameEnded(gameId, winner, player1.score, player2.score);
        emit GameStats(totalGames.get(), activeGames.get(), completedGames.get());
    }
    
    function forceEndGame(uint256 gameId) external {
        Game storage game = games[gameId];
        require(game.active, "Game not active");
        require(block.timestamp >= game.endTime, "Game still active");
        
        _endGame(gameId);
    }
    
    function getGameQuestion(uint256 gameId, uint256 questionId) external view returns (uint256 num1, uint256 num2, uint256 operation) {
        uint256 questionData = gameQuestions[gameId][questionId];
        num1 = questionData >> 128;
        num2 = (questionData >> 64) & 0xFFFFFFFFFFFFFFFF;
        operation = questionData & 0xFFFFFFFFFFFFFFFF;
    }
    
    function getPlayerStats(address player) external returns (uint256 totalScore, uint256 gamesPlayed, uint256 wins) {
        // Use get method to retrieve values - returns uint256
        totalScore = playerScores.get(player);
        gamesPlayed = playerGamesPlayed.get(player);
        wins = playerWins.get(player);
    }
    
    function getGlobalStats() external returns (uint256 total, uint256 active, uint256 completed) {
        total = totalGames.get();
        active = activeGames.get();
        completed = completedGames.get();
    }
}