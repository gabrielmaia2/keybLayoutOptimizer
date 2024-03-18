using Revise

using Base.Filesystem: cptree
using Printf: @sprintf
using Random: rand
using StableRNGs: LehmerRNG
using BenchmarkTools: @time
using CUDA: CuArray
using JSON: parse as jparse

includet("src/DataProcessing.jl")
includet("src/DrawKeyboard.jl")
includet("src/Types.jl")
includet("src/Utils.jl")
includet("src/DataStats.jl")
includet("src/FrequencyKeyboard.jl")
includet("src/KeyboardGenerator.jl")

includet("src/Genome.jl")
includet("src/KeyboardObjective.jl")
includet("src/SimulatedAnnealing.jl")

using .Utils: conditionalSplit, dictToArray, dictToNamedTuple, minMaxScale
using .DataProcessing: processDataFolderIntoTextFile
using .DataStats: computeStats
using .KeyboardGenerator: layoutGenerator, keyMapGenerator
using .DrawKeyboard: computeKeyboardColorMap, drawKeyboard
using .Types: RewardArgs, RewardMapArgs, LayoutKey, KeyboardData, CPUArgs, GPUArgs
using .FrequencyKeyboard: createFrequencyKeyMap, createFrequencyGenome, drawFrequencyKeyboard
using .KeyboardObjective: objectiveFunction
using .SimulatedAnnealing: runSA
using .Genome: shuffleKeyMap

function main(; useGPU, findWorst=false)
    jsonData = dictToNamedTuple(open(f -> jparse(f), "persistent/data.json", "r"))
    (;
        textPath,
        dataPaths,
        keyMap,
        noCharKeyMap,
        randomSeed,
        dataStats,
        keyboardLayout,
        fixedKeys,
        handFingers,
        algorithmArgs,
        keyboardSize,
        rewardArgs,
        saveLastRuns,
    ) = jsonData

    dataPaths = dictToNamedTuple(dataPaths)
    (; persistentPath, rawDataPath, dataPath, lastRunsPath, finalResultsPath, startResultsPath, endResultsPath) = dataPaths

    # Creating folders and removing old data
    map(i -> rm(joinpath(dataPath, "$i"), recursive=true), filter(s -> occursin(r"result", s), readdir(dataPath)))
    for path in dataPaths
        mkpath(path)
    end
    runId = 1 + last(sort(vcat([0], collect(map(i -> parse(Int, replace(i, r"[^0-9]" => "")), readdir(lastRunsPath))))))


    # TODO Split layout into list of keys with same size so that they can be shuffled
    keyMap = dictToNamedTuple(keyMap)
    keyMap = keyMapGenerator(
        startIndices=Vector{Int}(keyMap.startIndices),
        keys=Vector{String}(keyMap.keys)
    )
    keyMapCharacters = Set(keys(keyMap))
    noCharKeyMap = dictToNamedTuple(noCharKeyMap)
    noCharKeyMap = keyMapGenerator(
        startIndices=Vector{Int}(noCharKeyMap.startIndices),
        keys=Vector{Vector{String}}(noCharKeyMap.keys)
    )

    # Processing data
    processDataFolderIntoTextFile(rawDataPath, textPath, keyMapCharacters, overwrite=false, verbose=true)

    # Getting data
    textData = open(io -> read(io, String), textPath, "r")

    (; fingersCPS, rowsCPS) = dictToNamedTuple(dataStats)
    dataStats = computeStats(;
        text=textData,
        fingersCPS=Vector{Float64}(fingersCPS),
        rowsCPS=Vector{Float64}(rowsCPS)
    )

    (; textStats) = dataStats
    (; charFrequency) = textStats
    keyboardColorMap = computeKeyboardColorMap(charFrequency)

    layoutMap = layoutGenerator(; dictToNamedTuple(keyboardLayout)...)
    horizLayoutMap = [(x, y, w, h, finger, home, row) for ((x, y, w, h), (finger, home), row) in layoutMap] # No nested tuples
    # xMap, yMap, wMap, ....
    lmSymbols = ("$(i)Map" for i in ['x', 'y', 'w', 'h', "finger", "home", "row"])
    vertLayoutMap = NamedTuple{Tuple(Symbol.(lmSymbols))}(([k[i] for k in horizLayoutMap] for i in 1:7))
    (; xMap, yMap, homeMap) = vertLayoutMap
    vertLayoutMap = (hxMap=xMap[homeMap], hyMap=yMap[homeMap], vertLayoutMap...) # homes xs and ys

    fixedKeys = Set(fixedKeys)
    # const fixedKeys = collect("\t\n ") # Numbers also change
    getFixedMovableKeyMaps(keyMap) = conditionalSplit(((k, v),) -> k in fixedKeys, keyMap)
    fixedKeyMap, movableKeyMap = getFixedMovableKeyMaps(keyMap)
    movableKeys = [k for (k, v) in movableKeyMap]
    handFingers = Vector{Int}(handFingers)
    numFingers = length(handFingers)
    numKeys = length(keyMap)
    numLayoutKeys = length(layoutMap)
    numFixedKeys = length(fixedKeyMap)
    numMovableKeys = length(movableKeyMap)

    # Total number of iterations will be -epoch * log(t) / log(coolingRate)
    algorithmArgs = dictToNamedTuple(algorithmArgs)

    (; weights, yScale, distGrowthRate, rowsCPSBias) = dictToNamedTuple(rewardArgs)
    (; fingersCPS, rowsCPS, leftHand, doubleFinger, singleHand, distance) = dictToNamedTuple(weights)
    rewardWeighting = (fingersCPS, rowsCPS, leftHand)
    effortWeighting = (doubleFinger, singleHand, distance, sum(rewardWeighting)) # Adds weight for rewardMap

    rewardArgs = RewardArgs(;
        effortWeighting=NTuple{4,Float64}(effortWeighting),
        yScale=Float64(yScale),
        distGrowthRate=Float64(distGrowthRate),
    )

    rewardMapArgs = RewardMapArgs(;
        rewardWeighting=NTuple{3,Float64}(rewardWeighting),
        rowsCPSBias=NTuple{6,Float64}(rowsCPSBias),
    )

    keyboardData = KeyboardData(
        keyboardColorMap,
        layoutMap,
        vertLayoutMap,
        keyMapCharacters,
        keyMap,
        noCharKeyMap,
        fixedKeyMap,
        movableKeyMap,
        fixedKeys,
        movableKeys,
        getFixedMovableKeyMaps,
        handFingers,
        numFingers,
        numKeys,
        numLayoutKeys,
        numFixedKeys,
        numMovableKeys,
    )

    rewardKeyMap = createFrequencyKeyMap(dataStats, keyboardData, rewardMapArgs)
    frequencyGenome, freqKeyMap = createFrequencyGenome(dataStats, keyboardData, rewardKeyMap)

    td = collect(textData)

    cpuArgs = CPUArgs(
        text=td,
        layoutMap=layoutMap,
        handFingers=handFingers,
        rewardMap=rewardKeyMap,
    )

    gpuArgs = GPUArgs(
        numThreadsInBlock=512,
        text=CuArray(td),
        layoutMap=CuArray(layoutMap),
        handFingers=CuArray(handFingers),
        rewardMap=CuArray(rewardKeyMap),
    )

    (; numKeyboards) = algorithmArgs

    computationArgs = useGPU ? gpuArgs : cpuArgs
    compareGenomes = findWorst ? (>) : (<) # Usage: compareGenomes(new, old)

    rngs = LehmerRNG.(rand(LehmerRNG(randomSeed), 1:typemax(Int), numKeyboards))
    @inline genomeGenerator(i, rng) = i == 1 ? frequencyGenome : shuffleKeyMap(rng, keyMap, fixedKeys) # TODO CHECK

    println("Drawing frequency keymap...")
    drawFrequencyKeyboard(joinpath(finalResultsPath, "frequencyKeyboard.png"), frequencyGenome, freqKeyMap, keyboardData, useFrequencyColorMap=true)

    println(@sprintf "Raw baseline: %.2f" objectiveFunction(keyMap, computationArgs, rewardArgs))
    println("From here everything is reletive with + % worse and - % better than this baseline")

    saArgs = (
        computationArgs=computationArgs,
        rewardArgs=rewardArgs,
        keyboardData=keyboardData,
        algorithmArgs=algorithmArgs,
        compareGenomes=compareGenomes,
        rngs=rngs, # RNGs for each keyboard
        genomeGenerator=genomeGenerator # Function that generates starting keyboard
    )

    startGenomes, endGenomes = @time runSA(numKeyboards, saArgs, dataPaths, Val(useGPU))

    bestI, bestG, bestO = reduce(((i, g, o), (i2, g2, o2)) -> compareGenomes(o, o2) ? (i, g, o) : (i2, g2, o2), endGenomes)
    println("Best overall: $bestI; Score: $bestO")

    drawKeyboard(bestG, joinpath(finalResultsPath, "bestOverall.png"), keyboardData)
    saveLastRuns && cptree(finalResultsPath, joinpath(lastRunsPath, "$runId"))
end
