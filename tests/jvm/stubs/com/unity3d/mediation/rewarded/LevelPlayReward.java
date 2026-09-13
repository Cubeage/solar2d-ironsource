package com.unity3d.mediation.rewarded;

/** Minimal stand-in for com.unity3d.mediation.rewarded.LevelPlayReward. */
public final class LevelPlayReward {
    private final String name;
    private final int amount;

    public LevelPlayReward(String name, int amount) {
        this.name = name;
        this.amount = amount;
    }

    /** May return null, like the SDK when the reward has no name. */
    public String getName() {
        return name;
    }

    public int getAmount() {
        return amount;
    }
}
