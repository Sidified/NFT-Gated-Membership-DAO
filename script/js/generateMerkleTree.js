const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");
const fs = require("fs");
const path = require("path");

// Input: array of [address, votingPower] pairs
const claimants = [
    ["0xa19da2097332E962faabd6171587bcE04B7878Ef", 10],  // Your real wallet (Alice)
    ["0x70997970C51812dc3A010C7d01b50e0d17dc79C8", 20],  // Test Wallet 2 (Bob)
    ["0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", 30],  // Test Wallet 3 (Charlie)
    ["0x90F79bf6EB2c4f870365E785982E1f101E93b906", 40]   // Test Wallet 4 (David)
];

// Build the tree using OZ's standard format
const tree = StandardMerkleTree.of(claimants, ["address", "uint256"]);

console.log("Merkle Root:", tree.root);
console.log("--------------------------------------------------");

// Output proofs for each claimant
const output = {
    root: tree.root,
    claimants: {}
};

for (const [i, v] of tree.entries()) {
    const proof = tree.getProof(i);
    output.claimants[v[0]] = {
        votingPower: v[1],
        proof: proof
    };
    console.log(`Claimant ${v[0]} (power ${v[1]}):`);
    console.log(`Proof:`, proof);
    console.log("--------------------------------------------------");
}

// Ensure directory exists and save
const dir = "script/js";
if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
}

fs.writeFileSync(path.join(dir, "merkle-output.json"), JSON.stringify(output, null, 2));
console.log("Merkle tree data saved to script/js/merkle-output.json");