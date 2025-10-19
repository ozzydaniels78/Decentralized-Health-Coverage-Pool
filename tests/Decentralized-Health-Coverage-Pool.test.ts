import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

describe("Decentralized Health Coverage Pool", () => {
  it("should allow members to join the pool", () => {
    const { result } = simnet.callPublicFn(
      "health-pool",
      "join-pool", 
      [Cl.uint(1000000)],
      wallet1
    );
    
    expect(result).toBeOk(Cl.bool(true));
  });

  it("should reject joining with insufficient contribution", () => {
    const { result } = simnet.callPublicFn(
      "health-pool",
      "join-pool", 
      [Cl.uint(500000)], // 0.5 STX - below minimum
      wallet2
    );
    
    expect(result).toBeErr(Cl.uint(104)); // ERR-MINIMUM-CONTRIBUTION
  });

  it("should track pool statistics correctly", () => {
    // Join pool first
    simnet.callPublicFn("health-pool", "join-pool", [Cl.uint(2000000)], wallet1);
    
    // Check pool statistics
    const { result } = simnet.callReadOnlyFn(
      "health-pool", 
      "get-pool-stats", 
      [], 
      deployer
    );
    
    expect(result).toBeTuple({
      "balance": Cl.uint(2000000),
      "total-members": Cl.uint(1),
      "total-claims": Cl.uint(0),
      "min-contribution": Cl.uint(1000000),
      "max-claim": Cl.uint(5000000),
      "is-paused": Cl.bool(false)
    });
  });
});
