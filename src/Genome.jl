module Genome

using Random: randperm, shuffle

using ..Utils: conditionalSplit

export shuffleKeyMap, shuffleGenomeKeyMap

# Num keys should not exceed length(keyMap) - length(fixedKeys)
function shuffleKeyMap(rng, keyMap, fixedKeys; numKeys=nothing)
    fkm, skm = conditionalSplit(((k, v),) -> k in fixedKeys, deepcopy(keyMap))
    ks, vs = collect(keys(skm)), collect(values(skm))

    shuffledKeys = randperm(rng, length(vs))
    shuffledKeys = isnothing(numKeys) ? shuffledKeys : shuffledKeys[1:numKeys]
    vs[shuffledKeys] = shuffle(rng, copy(vs[shuffledKeys])) # Permutates keys

    d = Dict(zip(ks, vs))
    merge!(d, fkm)
    return d
end

function shuffleGenomeKeyMap(rng, genome, fixedKeys, numKeys)
    numMovableKeys = length(genome) - length(fixedKeys)
    numKeys = min(max(2, numKeys), numMovableKeys)

    # Prevents a shuffle that returns the exact same genome, losing time uselessly recomputing data
    newGenome = genome
    while newGenome == genome
        newGenome = shuffleKeyMap(rng, genome, fixedKeys; numKeys=numKeys)
    end

    return newGenome
end

end
