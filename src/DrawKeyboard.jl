module DrawKeyboard

using Plots
using Colors

# Hue goes from 170 (min f) to 0 (max f)
# Saturation is the normalized frequency of each key
normFreqToHSV(f) = HSV((1.0 - f) * 170, f * 0.7 + 0.3, 1.0)

function computeKeyboardColorMap(charFrequency)
    charFrequency = filter(((k, v),) -> !isspace(k), charFrequency)
    # Normalizes char frequency
    maxf = maximum(values(charFrequency))
    minf = minimum(values(charFrequency))

    return Dict(k => normFreqToHSV(log2(1 + (v - minf) / (maxf - minf))) for (k, v) in charFrequency)
end

function drawKey(key, letter, keyboardColorMap)
    (x, y, w), (finger, home), row = key
    h = 1 # TODO Add h to layout
    color = get(keyboardColorMap, lowercase(letter), HSV(220, 0.2, 1))
    border = Shape((x - 0.5 * w) .+ [0, w, w, 0], (y - 0.5 * h) .+ [0, 0, h, h])
    rect = Shape((x - 0.5 * w + 0.03) .+ ((w - 0.06) .* [0, 1, 1, 0]), (y - 0.5 * h + 0.03) .+ ((h - 0.06) .* [0, 0, 1, 1]))

    plot!(border, fillalpha=1, linecolor=nothing, color=HSV((finger - 1) * 720 / numFingers, 1, 1), label="", dpi=100) # Border
    plot!(rect, fillalpha=1, linecolor=nothing, color=HSVA(color, 0.5), label="", dpi=100)

    if home == 1
        #plot!(rect, fillalpha=0.2, linecolor=nothing, color=HSVA(0, 0, 0, 0.3), label="", dpi=100)
        plot!([x], [y - 0.33], shape=:rect, fillalpha=0.2, linecolor=nothing, color=HSV(0, 0, 0), label="", markersize=1.5, dpi=100)
    end

    # Draws character
    annotate!(x, y, text(uppercase(strip(string(letter == '\\' ? '|' : letter))), :black, :center, 8))
end

function drawKeyboard(myGenome, filepath, layoutMap, keyboardColorMap)
    plot(axis=([], false))

    for (letter, i) in myGenome
        drawKey(layoutMap[i], letter)
    end

    for (name, i) in noCharKeys
        drawKey(layoutMap[i], name)
    end

    plot!(aspect_ratio=1, legend=false)
    savefig(filepath)
end

function drawKeyboard(genome, filepath, layoutMap, keyboardColorMap, lk)
    if isnothing(lk)
        lk = ReentrantLock()
    end
    lock(lk) do
        drawKeyboard(genome, filepath, layoutMap, keyboardColorMap)
    end
end

export computeKeyboardColorMap, drawKeyboard

end
