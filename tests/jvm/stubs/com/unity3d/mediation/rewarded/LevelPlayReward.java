package com.unity3d.mediation.rewarded;

/** Minimal stand-in for com.unity3d.mediation.rewarded.LevelPlayReward. */
public final class LevelPlayReward {
    private final String name;
    private final int amount;

    public LevelPlayReward(String name, int amount) {
        this.name = name;
        this.amount = amount;
    }

    /**
     * The real SDK (9.3.0, bytecode-verified) rejects a null name in the constructor
     * ({@code Intrinsics.checkNotNullParameter}); this stub accepts null so the tests can
     * pin the plugin's defensive null policy on the dispatch path.
     */
    public String getName() {
        return name;
    }

    public int getAmount() {
        return amount;
    }
}
