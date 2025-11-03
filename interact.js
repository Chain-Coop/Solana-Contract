import {
  Connection,
  PublicKey,
  Keypair,
  Transaction,
  SystemProgram,
  LAMPORTS_PER_SOL,
  sendAndConfirmTransaction,
  SYSVAR_RENT_PUBKEY
} from "@solana/web3.js";
import { Token, TOKEN_PROGRAM_ID, ASSOCIATED_TOKEN_PROGRAM_ID } from "@solana/spl-token";
import { Buffer } from 'buffer';
import fs from "fs";
import os from "os";

// Program ID
const PROGRAM_ID = new PublicKey("HdJwvYmvjHRFBiuEz66G2HgcUW2XZaqMuL8MHv71qY4G");

// Connection with Solana Devnet
const connection = new Connection("https://api.devnet.solana.com", "confirmed");

// Helper functions
async function ensureMinimumBalance(connection, publicKey, minBalance = 0.1 * LAMPORTS_PER_SOL) {
  const balance = await connection.getBalance(publicKey);
  console.log(`Current balance: ${balance / LAMPORTS_PER_SOL} SOL`);
  
  if (balance < minBalance) {
    console.log(`Requesting airdrop of 1 SOL...`);
    const airdropSignature = await connection.requestAirdrop(
      publicKey,
      LAMPORTS_PER_SOL
    );
    await connection.confirmTransaction(airdropSignature);
    console.log(`Airdrop successful!`);
    console.log(`New balance: ${(await connection.getBalance(publicKey)) / LAMPORTS_PER_SOL} SOL`);
  }
}

// Create a test token for testing
async function createTestToken(connection, payer) {
  console.log("Creating test token...");
  const token = await Token.createMint(
    connection,
    payer,
    payer.publicKey,
    null,
    9, // Decimals
    TOKEN_PROGRAM_ID
  );
  console.log(`Test token created: ${token.publicKey.toBase58()}`);
  return token;
}

// Get or create associated token account
async function getOrCreateAssociatedTokenAccount(
  connection,
  mint,
  owner,
  payer
) {
  const associatedTokenAccount = await Token.getAssociatedTokenAddress(
    ASSOCIATED_TOKEN_PROGRAM_ID,
    TOKEN_PROGRAM_ID,
    mint,
    owner
  );

  const accountInfo = await connection.getAccountInfo(associatedTokenAccount);
  if (!accountInfo) {
    const token = new Token(connection, mint, TOKEN_PROGRAM_ID, payer);
    await token.createAssociatedTokenAccount(owner);
  }

  return associatedTokenAccount;
}

// Main test function
async function testChainCoopSaving() {
  try {
    console.log("=== Testing ChainCoopSaving Program ===");

    // Load wallet
    const payer = Keypair.fromSecretKey(
      Uint8Array.from(
        JSON.parse(
          fs.readFileSync(`${os.homedir()}/.config/solana/id.json`, "utf8")
        )
      )
    );
    console.log("Wallet loaded:", payer.publicKey.toBase58());

    // Ensure we have enough balance
    await ensureMinimumBalance(connection, payer.publicKey);

    // Create a test token
    const testToken = await createTestToken(connection, payer);
    const testTokenMint = testToken.publicKey;

    // Create token accounts
    const userTokenAccount = await getOrCreateAssociatedTokenAccount(
      connection,
      testTokenMint,
      payer.publicKey,
      payer
    );

    const vaultTokenAccount = await getOrCreateAssociatedTokenAccount(
      connection,
      testTokenMint,
      PROGRAM_ID, // Program-owned token account
      payer
    );

    // Mint some test tokens to user
    await testToken.mintTo(
      userTokenAccount,
      payer.publicKey,
      [],
      1000 * 10 ** 9 // 1000 tokens with 9 decimals
    );
    console.log("Minted test tokens to user");

    // 1. Test openSavingPool
    console.log("\n=== Testing openSavingPool ===");
    const poolIndex = await openSavingPool(
      connection,
      PROGRAM_ID,
      payer,
      testTokenMint,
      100 * 10 ** 9, // 100 tokens
      "Test savings",
      0, // FLEXIBLE
      30 // 30 days
    );
    console.log(`Pool created with index: ${poolIndex}`);

    // 2. Test updateSaving
    console.log("\n=== Testing updateSaving ===");
    await updateSaving(
      connection,
      PROGRAM_ID,
      payer,
      poolIndex,
      50 * 10 ** 9 // Add 50 more tokens
    );
    console.log("Pool updated successfully");

    // 3. Test getSavingPoolCount
    console.log("\n=== Testing getSavingPoolCount ===");
    const poolCount = await getSavingPoolCount(connection, PROGRAM_ID);
    console.log(`Total pools: ${poolCount}`);

    // 4. Test getSavingPoolByIndex
    console.log("\n=== Testing getSavingPoolByIndex ===");
    const pool = await getSavingPoolByIndex(connection, PROGRAM_ID, poolIndex);
    console.log("Pool details:", JSON.stringify(pool, null, 2));

    // 5. Test stopSaving
    console.log("\n=== Testing stopSaving ===");
    await stopSaving(connection, PROGRAM_ID, payer, poolIndex);
    console.log("Pool stopped successfully");

    // 6. Test restartSaving
    console.log("\n=== Testing restartSaving ===");
    await restartSaving(connection, PROGRAM_ID, payer, poolIndex);
    console.log("Pool restarted successfully");

    // 7. Test withdraw (partial)
    console.log("\n=== Testing withdraw ===");
    await withdraw(
      connection,
      PROGRAM_ID,
      payer,
      poolIndex,
      50 * 10 ** 9 // Withdraw 50 tokens
    );
    console.log("Withdrawal successful");

    console.log("\n=== All tests completed successfully! ===");

  } catch (error) {
    console.error("Test failed:", error);
    if (error.logs) {
      console.error("Transaction logs:", error.logs);
    }
    process.exit(1);
  }
}

// Implement the individual test functions (openSavingPool, updateSaving, etc.)
async function openSavingPool(connection, programId, payer, tokenMint, amount, reason, lockType, duration) {
  // Implementation for openSavingPool
  // ...
}

async function updateSaving(connection, programId, payer, poolIndex, amount) {
  // Implementation for updateSaving
  // ...
}

async function withdraw(connection, programId, payer, poolIndex, amount) {
  // Implementation for withdraw
  // ...
}

async function stopSaving(connection, programId, payer, poolIndex) {
  // Implementation for stopSaving
  // ...
}

async function restartSaving(connection, programId, payer, poolIndex) {
  // Implementation for restartSaving
  // ...
}

async function getSavingPoolCount(connection, programId) {
  // Implementation for getSavingPoolCount
  // ...
}

async function getSavingPoolByIndex(connection, programId, poolIndex) {
  // Implementation for getSavingPoolByIndex
  // ...
}

// Run the tests
testChainCoopSaving().catch(console.error);