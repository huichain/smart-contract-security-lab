// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleAMM} from "./SimpleAMM.sol";

/// @title TWAPOracle
/// @notice Records cumulative AMM spot prices so lending can use a time-weighted average
///         instead of a manipulable instantaneous spot price.
/// @dev Keepers (or anyone) should call `update()` periodically. `consult()` returns the
///      average price over `minWindow` seconds using stored observations.
contract TWAPOracle {
    uint8 public constant MAX_OBSERVATIONS = 8;

    SimpleAMM public immutable amm;
    uint32 public immutable minWindow;

    struct Observation {
        uint32 timestamp;
        uint256 priceCumulative;
    }

    Observation[MAX_OBSERVATIONS] internal observations;
    uint8 internal observationIndex;
    uint8 public observationCount;

    constructor(SimpleAMM amm_, uint32 minWindow_) {
        require(minWindow_ > 0, "zero window");

        amm = amm_;
        minWindow = minWindow_;
        _writeObservation();
    }

    /// @notice Snapshot the current cumulative price. Call this on a steady cadence.
    function update() external {
        _writeObservation();
    }

    /// @notice Returns the TWAP over `minWindow` seconds.
    function consult() external view returns (uint256) {
        return _consult(minWindow);
    }

    function _consult(uint32 window) internal view returns (uint256) {
        require(window > 0, "zero window");

        uint32 currentTime = uint32(block.timestamp);
        (uint256 cumulativeNow, ) = _currentCumulative();

        uint32 targetTime = currentTime - window;
        Observation memory anchor = _findObservationAtOrBefore(targetTime);
        require(anchor.timestamp <= targetTime, "insufficient history");
        require(currentTime > anchor.timestamp, "insufficient history");

        return (cumulativeNow - anchor.priceCumulative) / (currentTime - anchor.timestamp);
    }

    function _currentCumulative() internal view returns (uint256 cumulative, uint32 timestamp) {
        Observation memory last = observations[observationIndex];
        timestamp = uint32(block.timestamp);
        cumulative = last.priceCumulative;

        uint32 timeElapsed = timestamp - last.timestamp;
        if (timeElapsed > 0) {
            cumulative += uint256(timeElapsed) * amm.getSpotPrice();
        }
    }

    function _writeObservation() internal {
        (uint256 cumulative, uint32 timestamp) = _currentCumulative();

        uint8 newIndex = (observationIndex + 1) % MAX_OBSERVATIONS;
        observations[newIndex] = Observation({timestamp: timestamp, priceCumulative: cumulative});
        observationIndex = newIndex;

        if (observationCount < MAX_OBSERVATIONS) {
            observationCount++;
        }
    }

    function _findObservationAtOrBefore(uint32 targetTime) internal view returns (Observation memory anchor) {
        require(observationCount > 0, "no observations");

        bool found;
        for (uint8 i = 0; i < observationCount; i++) {
            uint8 idx = (observationIndex + MAX_OBSERVATIONS - i) % MAX_OBSERVATIONS;
            Observation memory obs = observations[idx];

            if (obs.timestamp <= targetTime) {
                anchor = obs;
                found = true;
                break;
            }
        }

        require(found, "insufficient history");
    }
}
