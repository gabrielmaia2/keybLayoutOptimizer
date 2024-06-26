module DrawKeyboard

using Plots: plot, plot!, annotate!, text, savefig, Shape, gui
using Colors: HSV, HSVA

export computeKeyboardColorMap, drawKeyboard

# Hue goes from 170 (min f) to 0 (max f)
# Saturation is the normalized frequency of each key
normFreqToHSV(f) = HSV((1.0 - f) * 170, f * 0.7 + 0.3, 1.0)

# Sorts chars and gives colors linearly, better for visualizing order of frequency
function computeKeyboardColorMap(charFrequency, linear::Val{true})
    charFrequency = filter(((k, v),) -> !isspace(k), charFrequency)

    d = Dict{Float64,Vector{Any}}()
    for (k, v) in charFrequency
        d[v] = get(d, v, [])
        push!(d[v], k)
    end

    res = sort(collect(d), by=((f, lc),) -> f)
    return Dict((c => normFreqToHSV((i - 1) / (length(res) - 1)) for (i, (_, lc)) in enumerate(res) for c in lc))
end

function computeKeyboardColorMap(charFrequency, linear::Val{false})
    charFrequency = filter(((k, v),) -> !isspace(k), charFrequency)
    # Normalizes char frequency
    maxf = maximum(values(charFrequency))
    minf = minimum(values(charFrequency))

    return Dict(k => normFreqToHSV(log2(1 + (v - minf) / (maxf - minf))) for (k, v) in charFrequency)
end

function drawKey(key, letter, layoutMap, keyboardData)
    (; keyboardColorMap, numFingers) = keyboardData
    (x, y, w, h), (finger, home), row = layoutMap[key]
    color = get(keyboardColorMap, lowercase(letter), HSV(220, 0.2, 1))
    border = Shape((x - 0.5 * w) .+ [0, w, w, 0], (y - 0.5 * h) .+ [0, 0, h, h])
    rect = Shape((x - 0.5 * w + 0.03) .+ ((w - 0.06) .* [0, 1, 1, 0]), (y - 0.5 * h + 0.03) .+ ((h - 0.06) .* [0, 0, 1, 1]))

    plot!(border, fillalpha=1, linecolor=nothing, color=HSV((finger - 1) * 720 / numFingers, 1, 1), label="", dpi=100) # Border
    plot!(rect, fillalpha=1, linecolor=nothing, color=HSVA(color, 0.5), label="", dpi=100)

    if home == key
        #plot!(rect, fillalpha=0.2, linecolor=nothing, color=HSVA(0, 0, 0, 0.3), label="", dpi=100)
        plot!([x], [y - 0.33], shape=:rect, fillalpha=0.2, linecolor=nothing, color=HSV(0, 0, 0), label="", markersize=1.5, dpi=100)
    end

    # Draws character
    annotate!(x, y, text(uppercase(strip(string(letter == '\\' ? '|' : letter))), :black, :center, 8))
end

function drawKeyboard(genome, keyboardData; filepath=nothing)
    (; layoutMap, noCharKeyMap) = keyboardData

    plot(axis=([], false))

    for (letter, i) in genome
        drawKey(i, letter, layoutMap, keyboardData)
    end

    for (name, i) in noCharKeyMap
        drawKey(i, name, layoutMap, keyboardData)
    end

    plot!(aspect_ratio=1, legend=false)
    isnothing(filepath) ? gui() : savefig(filepath)
end

function drawKeyboard(genome, keyboardData, lk; filepath=nothing)
    if isnothing(lk)
        drawKeyboard(genome, keyboardData, filepath=filepath)
        return
    end
    lock(lk) do
        drawKeyboard(genome, keyboardData, filepath=filepath)
    end
end

end
