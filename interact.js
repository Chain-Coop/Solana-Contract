// interact.js
import {
  Connection,
  PublicKey,
  Keypair,
  Transaction,
  SystemProgram,
  LAMPORTS_PER_SOL,
  sendAndConfirmTransaction
} from "@solana/web3.js";
import fs from "fs";
import os from "os";

// Program ID
const PROGRAM_ID = new PublicKey("HdJwvYmvjHRFBiuEz66G2HgcUW2XZaqMuL8MHv71qY4G");

// Connection with Solana Devnet
const connection = new Connection("https://api.devnet.solana.com", "confirmed");

// Helper function to request airdrop if needed
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

async function main() {
  try {
    console.log("Connecting to Solana Devnet...");

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

    // Create a new account for the recipient
    const recipient = Keypair.generate();
    console.log("Recipient account:", recipient.publicKey.toBase58());

    // Get the minimum rent exemption for the recipient account
    const rentExemptionAmount = await connection.getMinimumBalanceForRentExemption(0);
    console.log(`Minimum rent exemption: ${rentExemptionAmount} lamports`);

    // Create account and transfer some SOL in one transaction
    const createAccountIx = SystemProgram.createAccount({
      fromPubkey: payer.publicKey,
      newAccountPubkey: recipient.publicKey,
      lamports: rentExemptionAmount + 1000, // Rent + some extra SOL
      space: 0, // No data storage needed for this example
      programId: SystemProgram.programId,
    });

    const transaction = new Transaction().add(createAccountIx);
    
    console.log("Sending transaction...");
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer, recipient] // Both payer and recipient are signers
    );

    console.log("\nTransaction successful!");
    console.log(`Signature: ${signature}`);
    console.log(`Explorer: https://explorer.solana.com/tx/${signature}?cluster=devnet`);
    
    // Verify the transfer
    const recipientBalance = await connection.getBalance(recipient.publicKey);
    console.log(`Recipient balance: ${recipientBalance / LAMPORTS_PER_SOL} SOL`);

  } catch (error) {
    console.error("Error:", error);
    if (error.logs) {
      console.error("Transaction logs:", error.logs);
    }
  }
}

main();