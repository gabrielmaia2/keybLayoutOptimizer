module FrequencyKeyboard

using Setfield: @set
using LinearAlgebra: normalize

using ..Utils: conditionalSplit
using ..DrawKeyboard: computeKeyboardColorMap, drawKeyboard

export createFrequencyKeyMap, createFrequencyGenome, drawFrequencyKeyboard

function objective(key, dataStats, keyboardData, frequencyRewardArgs)
    (; effortWeighting, xBias, leftHandBias, rowsCPSBias, ansKbs) = frequencyRewardArgs
    (; fingersCPS, rowsCPS) = dataStats
    (; layoutMap, handFingers) = keyboardData

    (x, y, _), (finger, home), row = layoutMap[key]
    (hx, hy, _), _, _ = layoutMap[home]

    # Distance penalty
    dx, dy = x - hx, y - hy
    distanceReward = sqrt((dx * xBias * 2)^2 + (dy * (1 - xBias) * 2)^2) * ansKbs
    distanceReward = 2^1.5 - (1 + distanceReward)^1.5 / (2^1.5)

    # Finger and row reward
    # TODO change to bounds [0,1] and compute outside function
    fingerReward = normalize(fingersCPS)[finger] * normalize(rowsCPS .* rowsCPSBias)[row]

    # 1 for right hand, > 1 for left hand
    leftHandReward = 1 - leftHandBias + (2 - handFingers[finger]) * (2 * leftHandBias - 1)

    reward = sum((fingerReward, distanceReward) .* effortWeighting) * leftHandReward
    return reward
end

# Maps key ids to their rewards
function createFrequencyKeyMap(dataStats, keyboardData, frequencyRewardArgs)
    (; layoutMap) = keyboardData
    # TODO Map to [0, 1]
    return Dict(k => objective(k, dataStats, keyboardData, frequencyRewardArgs) for k in keys(layoutMap))
end

getSorted(keyMap) = map(((c, f),) -> c, sort(by=((c, f),) -> f, collect(keyMap)))

# Maps chars to their frequencies
function getFrequencyKeyMap(keyMap, charFrequency)
    cfks = Set(keys(charFrequency))
    keyMap1, keyMap2 = conditionalSplit(((k, v),) -> k in cfks, keyMap)
    keyMap1 = Dict(map(((k, v),) -> k => charFrequency[k], collect(keyMap1)))
    keyMap2 = Dict(map(((k, v),) -> k => 0, collect(keyMap2)))
    return merge(keyMap1, keyMap2)
end

function createFrequencyGenome(dataStats, keyboardData, rewardKeyMap)
    (; textStats) = dataStats
    (; charFrequency) = textStats
    (; keyMap, getFixedMovableKeyMaps, fixedKeys, fixedKeyMap) = keyboardData
    revFixedKeys = Set((keyMap[c] for c in fixedKeys)) # Keys instead of chars

    svkm = Set(values(keyMap))
    freqKeyMap, _ = conditionalSplit(((k, v),) -> k in svkm, rewardKeyMap)
    _, movableFreqKeyMap = conditionalSplit(((k, v),) -> k in revFixedKeys, freqKeyMap)

    charFrequency = getFrequencyKeyMap(keyMap, charFrequency) # Chars to real frequencies
    _, movableCharFrequency = getFixedMovableKeyMaps(charFrequency)

    mchars = getSorted(movableCharFrequency)
    mkeys = getSorted(movableFreqKeyMap)

    kmap = merge(Dict(zip(mchars, mkeys)), fixedKeyMap) # char => key
    freqkmap = Dict(c => freqKeyMap[k] for (c, k) in collect(kmap)) # char => f
    return kmap, freqkmap
end

function drawFrequencyKeyboard(filepath, genome, freqKeyMap, keyboardData; useFrequencyColorMap=false)
    kbData = keyboardData
    if useFrequencyColorMap == true
        kbData = @set keyboardData.keyboardColorMap = computeKeyboardColorMap(freqKeyMap)
    end

    drawKeyboard(genome, filepath, kbData)
end

end
