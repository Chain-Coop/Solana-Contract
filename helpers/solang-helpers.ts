import {
  Connection,
  PublicKey,
  Transaction,
  TransactionInstruction,
  Keypair,
  sendAndConfirmTransaction,
  SystemProgram,
} from '@solana/web3.js';
import { TOKEN_PROGRAM_ID } from '@solana/spl-token';
import { createHash } from 'crypto';

/**
 * Helper class for interacting with the ChainCoopSaving Solang contract
 */
export class ChainCoopSavingClient {
  constructor(
    private connection: Connection,
    private programId: PublicKey
  ) {}

  /**
   * Calculate the method selector (first 4 bytes of keccak256 hash)
   */
  private getMethodSelector(signature: string): Buffer {
    const hash = createHash('sha256').update(signature).digest();
    return hash.slice(0, 4);
  }

  /**
   * Get all method selectors for the contract
   */
  private get selectors() {
    return {
      initialize: this.getMethodSelector('initialize(address)'),
      openSavingPool: this.getMethodSelector('openSavingPool(address,uint64,string,uint8,uint64)'),
      updateSaving: this.getMethodSelector('updateSaving(bytes32,uint64)'),
      withdraw: this.getMethodSelector('withdraw(bytes32)'),
      stopSaving: this.getMethodSelector('stopSaving(bytes32)'),
      restartSaving: this.getMethodSelector('restartSaving(bytes32)'),
      setAllowedToken: this.getMethodSelector('setAllowedToken(address,bool)'),
      setTokenFilteringEnabled: this.getMethodSelector('setTokenFilteringEnabled(bool)'),
      setFeeRecipient: this.getMethodSelector('setFeeRecipient(address)'),
      getSavingPoolCount: this.getMethodSelector('getSavingPoolCount()'),
      getUserPoolCount: this.getMethodSelector('getUserPoolCount(address)'),
      getUserPoolIdByIndex: this.getMethodSelector('getUserPoolIdByIndex(address,uint64)'),
      isTokenAllowed: this.getMethodSelector('isTokenAllowed(address)'),
      getSavingPoolByIndex: this.getMethodSelector('getSavingPoolByIndex(bytes32)'),
    };
  }

  /**
   * Encode uint64 as little-endian bytes
   */
  private encodeU64(value: bigint | number): Buffer {
    const buf = Buffer.alloc(8);
    buf.writeBigUInt64LE(BigInt(value));
    return buf;
  }

  /**
   * Encode address (PublicKey) as 32 bytes
   */
  private encodeAddress(address: PublicKey): Buffer {
    return address.toBuffer();
  }

  /**
   * Encode bool as single byte
   */
  private encodeBool(value: boolean): Buffer {
    const buf = Buffer.alloc(1);
    buf.writeUInt8(value ? 1 : 0);
    return buf;
  }

  /**
   * Encode string as bytes32 (padded/truncated to 32 bytes)
   */
  private encodeBytes32String(str: string): Buffer {
    const buf = Buffer.alloc(32);
    const strBuf = Buffer.from(str, 'utf8');
    strBuf.copy(buf, 0, 0, Math.min(strBuf.length, 32));
    return buf;
  }

  /**
   * Encode LockingType enum
   */
  private encodeLockingType(lockType: 0 | 1 | 2): Buffer {
    const buf = Buffer.alloc(1);
    buf.writeUInt8(lockType);
    return buf;
  }

  /**
   * Find PDAs for the contract
   */
  findPDAs(user: PublicKey) {
    const [vaultAuthority, vaultBump] = PublicKey.findProgramAddressSync(
      [Buffer.from('vault')],
      this.programId
    );

    const [programData, programBump] = PublicKey.findProgramAddressSync(
      [Buffer.from('program_data')],
      this.programId
    );

    const [userPools, userPoolsBump] = PublicKey.findProgramAddressSync(
      [Buffer.from('user_pools'), user.toBuffer()],
      this.programId
    );

    const [userBalance, userBalanceBump] = PublicKey.findProgramAddressSync(
      [Buffer.from('user_balance'), user.toBuffer()],
      this.programId
    );

    return {
      vaultAuthority: { address: vaultAuthority, bump: vaultBump },
      programData: { address: programData, bump: programBump },
      userPools: { address: userPools, bump: userPoolsBump },
      userBalance: { address: userBalance, bump: userBalanceBump },
    };
  }

  /**
   * Find pool PDA
   */
  findPoolPDA(user: PublicKey, poolIndex: number): { address: PublicKey; bump: number } {
    const [poolAddress, bump] = PublicKey.findProgramAddressSync(
      [Buffer.from('pool'), user.toBuffer(), Buffer.from([poolIndex])],
      this.programId
    );
    return { address: poolAddress, bump };
  }

  /**
   * Initialize the contract
   */
  async initialize(
    owner: Keypair,
    feeRecipient: PublicKey
  ): Promise<string> {
    const pdas = this.findPDAs(owner.publicKey);
    
    const data = Buffer.concat([
      this.selectors.initialize,
      this.encodeAddress(feeRecipient),
    ]);

    const instruction = new TransactionInstruction({
      keys: [
        { pubkey: owner.publicKey, isSigner: true, isWritable: true },
        { pubkey: pdas.programData.address, isSigner: false, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId: this.programId,
      data,
    });

    const transaction = new Transaction().add(instruction);
    return await sendAndConfirmTransaction(
      this.connection,
      transaction,
      [owner],
      { commitment: 'confirmed' }
    );
  }

  /**
   * Open a new saving pool
   */
  async openSavingPool(
    user: Keypair,
    tokenMint: PublicKey,
    amount: bigint,
    reason: string,
    lockType: 0 | 1 | 2, // 0=FLEXIBLE, 1=LOCK, 2=STRICTLOCK
    duration: bigint,
    userTokenAccount: PublicKey,
    vaultTokenAccount: PublicKey,
    owner: PublicKey,
    poolIndex: number = 0
  ): Promise<string> {
    const pdas = this.findPDAs(user.publicKey);
    const poolPDA = this.findPoolPDA(user.publicKey, poolIndex);

    const data = Buffer.concat([
      this.selectors.openSavingPool,
      this.encodeAddress(tokenMint),
      this.encodeU64(amount),
      this.encodeBytes32String(reason),
      this.encodeLockingType(lockType),
      this.encodeU64(duration),
    ]);

    const instruction = new TransactionInstruction({
      keys: [
        { pubkey: user.publicKey, isSigner: true, isWritable: true },
        { pubkey: poolPDA.address, isSigner: false, isWritable: true },
        { pubkey: pdas.userPools.address, isSigner: false, isWritable: true },
        { pubkey: pdas.userBalance.address, isSigner: false, isWritable: true },
        { pubkey: userTokenAccount, isSigner: false, isWritable: true },
        { pubkey: vaultTokenAccount, isSigner: false, isWritable: true },
        { pubkey: owner, isSigner: false, isWritable: false },
        { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId: this.programId,
      data,
    });

    const transaction = new Transaction().add(instruction);
    return await sendAndConfirmTransaction(
      this.connection,
      transaction,
      [user],
      { commitment: 'confirmed' }
    );
  }

  /**
   * Update an existing saving pool
   */
  async updateSaving(
    user: Keypair,
    poolId: Buffer,
    amount: bigint,
    userTokenAccount: PublicKey,
    vaultTokenAccount: PublicKey,
    poolPDA: PublicKey
  ): Promise<string> {
    const pdas = this.findPDAs(user.publicKey);

    const data = Buffer.concat([
      this.selectors.updateSaving,
      poolId,
      this.encodeU64(amount),
    ]);

    const instruction = new TransactionInstruction({
      keys: [
        { pubkey: user.publicKey, isSigner: true, isWritable: true },
        { pubkey: poolPDA, isSigner: false, isWritable: true },
        { pubkey: pdas.userBalance.address, isSigner: false, isWritable: true },
        { pubkey: userTokenAccount, isSigner: false, isWritable: true },
        { pubkey: vaultTokenAccount, isSigner: false, isWritable: true },
        { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
      ],
      programId: this.programId,
      data,
    });

    const transaction = new Transaction().add(instruction);
    return await sendAndConfirmTransaction(
      this.connection,
      transaction,
      [user],
      { commitment: 'confirmed' }
    );
  }

  /**
   * Withdraw from a saving pool
   */
  async withdraw(
    user: Keypair,
    poolId: Buffer,
    poolPDA: PublicKey,
    userTokenAccount: PublicKey,
    vaultTokenAccount: PublicKey,
    vaultAuthority: PublicKey,
    feeTokenAccount: PublicKey
  ): Promise<string> {
    const pdas = this.findPDAs(user.publicKey);

    const data = Buffer.concat([
      this.selectors.withdraw,
      poolId,
    ]);

    const instruction = new TransactionInstruction({
      keys: [
        { pubkey: user.publicKey, isSigner: true, isWritable: true },
        { pubkey: poolPDA, isSigner: false, isWritable: true },
        { pubkey: pdas.userPools.address, isSigner: false, isWritable: true },
        { pubkey: pdas.userBalance.address, isSigner: false, isWritable: true },
        { pubkey: userTokenAccount, isSigner: false, isWritable: true },
        { pubkey: vaultTokenAccount, isSigner: false, isWritable: true },
        { pubkey: vaultAuthority, isSigner: false, isWritable: false },
        { pubkey: feeTokenAccount, isSigner: false, isWritable: true },
        { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
      ],
      programId: this.programId,
      data,
    });

    const transaction = new Transaction().add(instruction);
    return await sendAndConfirmTransaction(
      this.connection,
      transaction,
      [user],
      { commitment: 'confirmed' }
    );
  }

  /**
   * Stop a saving pool
   */
  async stopSaving(
    user: Keypair,
    poolId: Buffer,
    poolPDA: PublicKey
  ): Promise<string> {
    const data = Buffer.concat([
      this.selectors.stopSaving,
      poolId,
    ]);

    const instruction = new TransactionInstruction({
      keys: [
        { pubkey: user.publicKey, isSigner: true, isWritable: true },
        { pubkey: poolPDA, isSigner: false, isWritable: true },
      ],
      programId: this.programId,
      data,
    });

    const transaction = new Transaction().add(instruction);
    return await sendAndConfirmTransaction(
      this.connection,
      transaction,
      [user],
      { commitment: 'confirmed' }
    );
  }

  /**
   * Restart a stopped saving pool
   */
  async restartSaving(
    user: Keypair,
    poolId: Buffer,
    poolPDA: PublicKey
  ): Promise<string> {
    const data = Buffer.concat([
      this.selectors.restartSaving,
      poolId,
    ]);

    const instruction = new TransactionInstruction({
      keys: [
        { pubkey: user.publicKey, isSigner: true, isWritable: true },
        { pubkey: poolPDA, isSigner: false, isWritable: true },
      ],
      programId: this.programId,
      data,
    });

    const transaction = new Transaction().add(instruction);
    return await sendAndConfirmTransaction(
      this.connection,
      transaction,
      [user],
      { commitment: 'confirmed' }
    );
  }

  /**
   * Set allowed token (owner only)
   */
  async setAllowedToken(
    owner: Keypair,
    token: PublicKey,
    allowed: boolean
  ): Promise<string> {
    const data = Buffer.concat([
      this.selectors.setAllowedToken,
      this.encodeAddress(token),
      this.encodeBool(allowed),
    ]);

    const instruction = new TransactionInstruction({
      keys: [
        { pubkey: owner.publicKey, isSigner: true, isWritable: true },
      ],
      programId: this.programId,
      data,
    });

    const transaction = new Transaction().add(instruction);
    return await sendAndConfirmTransaction(
      this.connection,
      transaction,
      [owner],
      { commitment: 'confirmed' }
    );
  }

  /**
   * Set token filtering enabled (owner only)
   */
  async setTokenFilteringEnabled(
    owner: Keypair,
    enabled: boolean
  ): Promise<string> {
    const data = Buffer.concat([
      this.selectors.setTokenFilteringEnabled,
      this.encodeBool(enabled),
    ]);

    const instruction = new TransactionInstruction({
      keys: [
        { pubkey: owner.publicKey, isSigner: true, isWritable: true },
      ],
      programId: this.programId,
      data,
    });

    const transaction = new Transaction().add(instruction);
    return await sendAndConfirmTransaction(
      this.connection,
      transaction,
      [owner],
      { commitment: 'confirmed' }
    );
  }

  /**
   * Set fee recipient (owner only)
   */
  async setFeeRecipient(
    owner: Keypair,
    feeRecipient: PublicKey
  ): Promise<string> {
    const data = Buffer.concat([
      this.selectors.setFeeRecipient,
      this.encodeAddress(feeRecipient),
    ]);

    const instruction = new TransactionInstruction({
      keys: [
        { pubkey: owner.publicKey, isSigner: true, isWritable: true },
      ],
      programId: this.programId,
      data,
    });

    const transaction = new Transaction().add(instruction);
    return await sendAndConfirmTransaction(
      this.connection,
      transaction,
      [owner],
      { commitment: 'confirmed' }
    );
  }

  /**
   * Calculate pool ID (mimics contract's _makePoolId)
   */
  calculatePoolId(saver: PublicKey, index: number, startDate: number): Buffer {
    const hash = createHash('sha256');
    hash.update(saver.toBuffer());
    hash.update(Buffer.from([index]));
    
    const dateBuf = Buffer.alloc(8);
    dateBuf.writeBigUInt64LE(BigInt(startDate));
    hash.update(dateBuf);
    
    return hash.digest();
  }

  /**
   * Calculate 3% fee
   */
  calculateFee(amount: bigint): bigint {
    return (amount * BigInt(3)) / BigInt(100);
  }
}

/**
 * Export enums and types
 */
export enum LockingType {
  FLEXIBLE = 0,
  LOCK = 1,
  STRICTLOCK = 2,
}

export interface SavingPool {
  saver: PublicKey;
  tokenToSaveWith: PublicKey;
  reason: Buffer;
  poolIndex: Buffer;
  startDate: bigint;
  duration: bigint;
  amountSaved: bigint;
  locktype: LockingType;
  isGoalAccomplished: boolean;
  isStopped: boolean;
}

/**
 * Usage example
 */
export async function example() {
  const connection = new Connection('http://localhost:8899', 'confirmed');
  const programId = new PublicKey('BL5SGpdGfmZNMv41uKehAZtjMv4nqk38X2JCXL6VZQFT');
  
  const client = new ChainCoopSavingClient(connection, programId);
  
  // Example: Initialize contract
  const owner = Keypair.generate();
  const feeRecipient = Keypair.generate();
  
  try {
    const sig = await client.initialize(owner, feeRecipient.publicKey);
    console.log('Initialized:', sig);
  } catch (error) {
    console.error('Error:', error);
  }
}