// interact.js
import {
  Connection,
  PublicKey,
  Keypair,
  Transaction,
  SystemProgram,
  sendAndConfirmTransaction
} from "@solana/web3.js";

import fs from "fs";
import os from "os";

// Program ID (unused for now)
const PROGRAM_ID = new PublicKey("HdJwvYmvjHRFBiuEz66G2HgcUW2XZaqMuL8MHv71qY4G");

// Connection with Solana Devnet
const connection = new Connection("https://api.devnet.solana.com", "confirmed");

async function main() {
  console.log("Connecting to Solana Devnet...");

  // Load wallet (default Solana CLI keypair)
  const payer = Keypair.fromSecretKey(
    Uint8Array.from(
      JSON.parse(
        fs.readFileSync(`${os.homedir()}/.config/solana/id.json`, "utf8")
      )
    )
  );

  console.log("Wallet loaded:", payer.publicKey.toBase58());

  // Use a test recipient (can be yourself or a new wallet)
  const recipient = Keypair.generate().publicKey;

  const instruction = SystemProgram.transfer({
    fromPubkey: payer.publicKey,
    toPubkey: recipient,
    lamports: 1000, // small amount for testing
  });

  const transaction = new Transaction().add(instruction);
  const signature = await sendAndConfirmTransaction(connection, transaction, [payer]);

  console.log("Transaction successful!");
  console.log("Signature:", signature);
}

main().catch(console.error);
