// Writes vectors.txt: the reference values test_crypto.cpp holds the
// firmware to. Wallets come from the ethers library, hashes from Node's
// crypto module, and the field arithmetic from JavaScript's own big
// integers — none of it from the code under test.
//
//   npm install ethers
//   node make_vectors.js > vectors.txt
//
// Every line is one case, tab-separated; see test_crypto.cpp for the
// columns. The random cases differ from run to run, which is the point.
const crypto = require("crypto");
const { ethers } = require("ethers");

const lines = [];
const emit = (...fields) => lines.push(fields.join("\t"));

// ── W: entropy → phrase → seed → private key → public key → address ──
function wallet(entropyHex) {
  const mnemonic = ethers.Mnemonic.fromEntropy("0x" + entropyHex);
  const node = ethers.HDNodeWallet.fromMnemonic(mnemonic, "m/44'/60'/0'/0/0");
  emit("W", entropyHex, mnemonic.phrase, mnemonic.computeSeed().slice(2), node.privateKey.slice(2),
       node.signingKey.publicKey.slice(2), node.address);
}

for (const bytes of [16, 32]) {
  wallet("00".repeat(bytes));             // "abandon … about" / "abandon … art"
  wallet("ff".repeat(bytes));
  wallet("7f".repeat(bytes));
}
for (let i = 0; i < 40; i++) wallet(crypto.randomBytes(i % 2 ? 32 : 16).toString("hex"));

// ── H: message, HMAC key, SHA-256, SHA-512, HMAC-SHA512, Keccak-256 ──
// Lengths sit on and around the block boundaries of each hash.
for (const length of [0, 1, 55, 56, 63, 64, 65, 111, 112, 119, 120, 127, 128, 129, 135, 136, 137, 200, 300]) {
  const message = crypto.randomBytes(length);
  const key = crypto.randomBytes(length % 7 === 0 ? 200 : 32);    // some keys longer than a block
  emit("H", message.toString("hex") || "-", key.toString("hex"),
       crypto.createHash("sha256").update(message).digest("hex"),
       crypto.createHash("sha512").update(message).digest("hex"),
       crypto.createHmac("sha512", key).update(message).digest("hex"),
       ethers.keccak256(message).slice(2));
}

// ── F: a, b, a*b mod p, a+b mod p, a-b mod p ──
const P = (1n << 256n) - (1n << 32n) - 977n;
const hex = (value) => value.toString(16).padStart(64, "0");
const random = () => BigInt("0x" + crypto.randomBytes(32).toString("hex")) % P;

// Values that sit at the edges of the reduction, each against each.
const edges = [0n, 1n, 2n, P - 1n, P - 2n, P - 977n, 1n << 255n, (1n << 256n) - (1n << 33n), (1n << 32n) + 977n,
               (1n << 224n) - 1n].map((value) => value % P);
const pairs = [];
for (const a of edges) for (const b of edges) pairs.push([a, b]);
for (let i = 0; i < 120; i++) pairs.push([random(), random()]);
for (let i = 0; i < 40; i++) pairs.push([P - BigInt(1 + i * 7919), P - BigInt(3 + i * 104729)]);
for (const [a, b] of pairs) emit("F", hex(a), hex(b), hex((a * b) % P), hex((a + b) % P), hex((a - b + P) % P));

console.log(lines.join("\n"));
