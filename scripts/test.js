const hre = require("hardhat");
const fs = require('fs');
const path = require('path');
var frontendUtil = require('@arcologynetwork/frontend-util/utils/util')
const nets = require('../network.json');
const ProgressBar = require('progress');

// Helper function to create directories recursively
function ensureDirectoryExists(dirPath) {
    if (!fs.existsSync(dirPath)) {
        fs.mkdirSync(dirPath, { recursive: true });
    }
}

async function main() {
    const accounts = await hre.ethers.getSigners();
    const provider = new hre.ethers.providers.JsonRpcProvider(nets[hre.network.name].url);
    const pkCreator = nets[hre.network.name].accounts[0];
    const signerCreator = new hre.ethers.Wallet(pkCreator, provider);
    const txbase = 'benchmark/ganit/txs';
    
    // Create the base directory structure
    ensureDirectoryExists(txbase);
    ensureDirectoryExists(path.join(txbase, 'create-games'));
    ensureDirectoryExists(path.join(txbase, 'submit-answers'));
    ensureDirectoryExists(path.join(txbase, 'end-games'));

    console.log('======start deploying contract======');
    const ganit_factory = await hre.ethers.getContractFactory("Ganit");
    const ganit = await ganit_factory.deploy();
    await ganit.deployed();
    console.log(`Deployed Ganit at ${ganit.address}`);

    const gameCount = 1000; // Number of parallel games
    const answersPerGame = 20; // Number of answers per game
    let i, tx;

    // Generate game creation transactions
    console.log('======start generating game creation TXs======');
    const handle_create = frontendUtil.newFile(txbase + '/create-games/create.out');

    const bar1 = new ProgressBar('Generating Game Creation Tx data [:bar] :percent :etas', {
        total: 100,
        width: 40,
        complete: '*',
        incomplete: ' ',
    });

    for (i = 0; i < gameCount; i++) {
        const player1Index = (i * 2) % accounts.length;
        const player2Index = (i * 2 + 1) % accounts.length;
        
        // Create wallet for this transaction
        const wallet = new hre.ethers.Wallet(nets[hre.network.name].accounts[player1Index % nets[hre.network.name].accounts.length], provider);
        
        // Get transaction data without from field
        tx = await ganit.populateTransaction.createGame(accounts[player2Index].address);
        
        // Remove the from field to avoid mismatch
        delete tx.from;
        
        await frontendUtil.writePreSignedTxFile(handle_create, wallet, tx);

        if (i > 0 && i % (gameCount / 100) == 0) {
            bar1.tick(1);
        }
    }
    bar1.tick(1);
    console.log(`Game creation tx generation completed: ${gameCount}`);

    // Generate answer submission transactions
    console.log('======start generating answer submission TXs======');
    const handle_answers = frontendUtil.newFile(txbase + '/submit-answers/answers.out');

    const bar2 = new ProgressBar('Generating Answer Submission Tx data [:bar] :percent :etas', {
        total: 100,
        width: 40,
        complete: '*',
        incomplete: ' ',
    });

    const totalAnswerTxs = gameCount * answersPerGame * 2; // 2 players per game
    let answerTxCount = 0;

    for (i = 0; i < gameCount; i++) {
        const gameId = generateGameId(i, accounts);
        
        for (let questionId = 0; questionId < answersPerGame; questionId++) {
            // Player 1 answers
            const player1Index = (i * 2) % accounts.length;
            const wallet1 = new hre.ethers.Wallet(nets[hre.network.name].accounts[player1Index % nets[hre.network.name].accounts.length], provider);
            const answer1 = generateRandomAnswer(gameId, questionId);
            tx = await ganit.populateTransaction.submitAnswer(gameId, questionId, answer1);
            delete tx.from; // Remove from field
            await frontendUtil.writePreSignedTxFile(handle_answers, wallet1, tx);
            answerTxCount++;

            // Player 2 answers
            const player2Index = (i * 2 + 1) % accounts.length;
            const wallet2 = new hre.ethers.Wallet(nets[hre.network.name].accounts[player2Index % nets[hre.network.name].accounts.length], provider);
            const answer2 = generateRandomAnswer(gameId, questionId);
            tx = await ganit.populateTransaction.submitAnswer(gameId, questionId, answer2);
            delete tx.from; // Remove from field
            await frontendUtil.writePreSignedTxFile(handle_answers, wallet2, tx);
            answerTxCount++;

            if (answerTxCount % Math.max(1, Math.floor(totalAnswerTxs / 100)) == 0) {
                bar2.tick(1);
            }
        }
    }
    bar2.tick(1);
    console.log(`Answer submission tx generation completed: ${answerTxCount}`);

    // Generate game ending transactions
    console.log('======start generating game ending TXs======');
    const handle_end = frontendUtil.newFile(txbase + '/end-games/end.out');

    for (i = 0; i < gameCount; i++) {
        const gameId = generateGameId(i, accounts);
        const signerIndex = i % nets[hre.network.name].accounts.length;
        const wallet = new hre.ethers.Wallet(nets[hre.network.name].accounts[signerIndex], provider);
        
        tx = await ganit.populateTransaction.forceEndGame(gameId);
        delete tx.from; // Remove from field
        await frontendUtil.writePreSignedTxFile(handle_end, wallet, tx);
    }
    console.log(`Game ending tx generation completed: ${gameCount}`);
}

function generateGameId(index, accounts) {
    // Use hre.ethers instead of ethers
    return hre.ethers.utils.keccak256(hre.ethers.utils.defaultAbiCoder.encode(
        ['uint256', 'address', 'address', 'uint256'],
        [Date.now() + index, accounts[index * 2 % accounts.length].address, accounts[(index * 2 + 1) % accounts.length].address, index]
    ));
}

function generateRandomAnswer(gameId, questionId) {
    // Generate realistic but mostly incorrect answers to simulate real gameplay
    const random = Math.random();
    if (random < 0.3) {
        // 30% chance of correct answer (simulate skilled players)
        return calculateCorrectAnswer(gameId, questionId);
    } else {
        // 70% chance of incorrect answer
        return Math.floor(Math.random() * 100) + 1;
    }
}

function calculateCorrectAnswer(gameId, questionId) {
    // Use hre.ethers instead of ethers
    const seed = hre.ethers.utils.keccak256(hre.ethers.utils.defaultAbiCoder.encode(['bytes32', 'uint256'], [gameId, questionId]));
    const seedNum = hre.ethers.BigNumber.from(seed);
    
    const num1 = seedNum.mod(50).add(1).toNumber();
    const num2 = seedNum.shr(8).mod(30).add(1).toNumber();
    const operation = seedNum.shr(16).mod(3).toNumber();
    
    if (operation === 0) return num1 + num2;
    if (operation === 1) return Math.abs(num1 - num2);
    return (num1 % 12 + 1) * (num2 % 12 + 1);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });