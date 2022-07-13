// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

interface IReferralStaking {
    // Events
    event Deposit(address user, uint8 tier);
    event Downgrade(address user, uint8 tier);
    event WithdrawAll(address user);
    event NewTier(uint8 index, uint256 rate, uint256 stake);
    event LastTierRemoved();
    event UpdateTimelock(uint256 timelockPeriod);

    // Errors
    error WrongDepositAmount();
    error NoFundsStaked();
    error StakingTierDoesntExist();
    error TierTooHigh();
    error UserAlreadyStaking();
    error FundsTimelocked();
}