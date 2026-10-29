// Writes session_vectors.txt: the reference values test_session.cpp
// holds the encrypted-session code to (cold_aes.h, cold_p256.h). AES,
// HMAC, P-256 and ECDSA come from Node's crypto module; AES-CMAC is
// written out below on top of Node's AES and checked against RFC 4493
// first. None of it comes from the code under test.
//
//   node make_session_vectors.js > session_vectors.txt
//
// Every line is one case, tab-separated; see test_session.cpp for the
// columns. The random cases differ from run to run, which is the point.
const crypto = require("crypto");
const assert = require("assert");

const lines = [];
const emit = (...fields) => lines.push(fields.join("\t"));
const hex = (buffer) => buffer.toString("hex") || "-";

// ── AES-128 and CMAC ─────────────────────────────────────────
function aesBlock(key, block) {
  const cipher = crypto.createCipheriv("aes-128-ecb", key, null);
  cipher.setAutoPadding(false);
  return Buffer.concat([cipher.update(block), cipher.final()]);
}

function xor(a, b) {
  return Buffer.from(a.map((byte, i) => byte ^ b[i]));
}

// One CMAC subkey from the one before (RFC 4493 §2.3).
function double(block) {
  const out = Buffer.alloc(16);
  for (let i = 0; i < 16; i++) out[i] = ((block[i] << 1) | (i < 15 ? block[i + 1] >> 7 : 0)) & 0xff;
  if (block[0] & 0x80) out[15] ^= 0x87;
  return out;
}

function cmac(key, message) {
  const k1 = double(aesBlock(key, Buffer.alloc(16)));
  const k2 = double(k1);
  const blocks = Math.max(1, Math.ceil(message.length / 16));
  const complete = message.length > 0 && message.length % 16 === 0;
  let x = Buffer.alloc(16);
  for (let i = 0; i < blocks - 1; i++) x = aesBlock(key, xor(x, message.subarray(i * 16, i * 16 + 16)));
  const tail = message.subarray((blocks - 1) * 16);
  let last = Buffer.alloc(16);
  if (complete) {
    last = xor(tail, k1);
  } else {
    tail.copy(last);
    last[tail.length] = 0x80;
    last = xor(last, k2);
  }
  return aesBlock(key, xor(x, last));
}

// RFC 4493 §4, before anything is written.
{
  const key = Buffer.from("2b7e151628aed2a6abf7158809cf4f3c", "hex");
  const message = Buffer.from("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51"
    + "30c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710", "hex");
  assert.strictEqual(cmac(key, message.subarray(0, 0)).toString("hex"), "bb1d6929e95937287fa37d129b756746");
  assert.strictEqual(cmac(key, message.subarray(0, 16)).toString("hex"), "070a16b46b4d4144f79bdd9dd04a287c");
  assert.strictEqual(cmac(key, message.subarray(0, 40)).toString("hex"), "dfa66747de9ae63030ca32611497c827");
  assert.strictEqual(cmac(key, message).toString("hex"), "51f0bebf7e3b9d92fc49741779363cfe");
}

// A: key, plaintext block, ciphertext block
for (let i = 0; i < 20; i++) {
  const key = crypto.randomBytes(16), block = crypto.randomBytes(16);
  emit("A", hex(key), hex(block), hex(aesBlock(key, block)));
}

// B: key, iv, plaintext, ciphertext (CBC, whole blocks, no padding)
for (const blocks of [1, 2, 3, 8]) {
  const key = crypto.randomBytes(16), iv = crypto.randomBytes(16), plain = crypto.randomBytes(blocks * 16);
  const cipher = crypto.createCipheriv("aes-128-cbc", key, iv);
  cipher.setAutoPadding(false);
  emit("B", hex(key), hex(iv), hex(plain), hex(Buffer.concat([cipher.update(plain), cipher.final()])));
}

// C: key, message, CMAC — lengths on and around the block boundaries
for (const length of [0, 1, 15, 16, 17, 31, 32, 33, 47, 48, 64, 100, 141]) {
  const key = crypto.randomBytes(16), message = crypto.randomBytes(length);
  emit("C", hex(key), hex(message), hex(cmac(key, message)));
}

// M: key, message, HMAC-SHA256 — some keys longer than a block
for (const length of [0, 1, 32, 55, 56, 64, 65, 100, 200]) {
  const key = crypto.randomBytes(length % 3 === 0 ? 80 : 32), message = crypto.randomBytes(length);
  emit("M", hex(key), hex(message), crypto.createHmac("sha256", key).update(message).digest("hex"));
}

// ── P-256 ────────────────────────────────────────────────────
const n = BigInt("0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551");
const scalar = (value) => Buffer.from(value.toString(16).padStart(64, "0"), "hex");

// P: private key, its public key, a peer's public key, the ECDH secret
function p256(privateKey) {
  const ecdh = crypto.createECDH("prime256v1");
  ecdh.setPrivateKey(privateKey);
  const peer = crypto.createECDH("prime256v1");
  peer.generateKeys();
  emit("P", hex(privateKey), hex(ecdh.getPublicKey()), hex(peer.getPublicKey()),
       hex(ecdh.computeSecret(peer.getPublicKey())));
}
p256(scalar(1n));
p256(scalar(2n));
p256(scalar(n - 1n));
p256(scalar(BigInt("0xc9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")));   // RFC 6979 A.2.5
for (let i = 0; i < 20; i++) {
  const ecdh = crypto.createECDH("prime256v1");
  ecdh.generateKeys();
  p256(Buffer.from(ecdh.getPrivateKey().toString("hex").padStart(64, "0"), "hex"));
}

// S: public key, message, an ECDSA-SHA256 signature by Node (DER)
for (const length of [0, 1, 32, 104, 300]) {
  const { publicKey, privateKey } = crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const jwk = publicKey.export({ format: "jwk" });
  const point = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, "base64url"), Buffer.from(jwk.y, "base64url")]);
  const message = crypto.randomBytes(length);
  emit("S", hex(point), hex(message), hex(crypto.sign("sha256", message, privateKey)));
}

process.stdout.write(lines.join("\n") + "\n");
